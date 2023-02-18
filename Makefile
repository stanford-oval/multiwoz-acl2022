geniedir ?= $(HOME)/genie-toolkit
NULL =

-include ../config.mk

#memsize := $(shell echo $$(($$(grep MemTotal /proc/meminfo | sed 's/[^0-9]//g')/1000-2500)))
memsize := 9000
#parallel := $(shell echo $$(($$(grep processor /proc/cpuinfo | wc -l)-1)))
parallel := 6
genie = node --experimental_worker --max_old_space_size=$(memsize) $(geniedir)/dist/tool/genie.js

all_experiments = multidomain
experiment ?= multidomain

# eval, eval_fewshot, or test
eval_set ?= eval test
template_file ?= thingtalk/en/dialogue.genie
dataset_file ?= $(experiment)/dataset.tt
synthetic_flags ?= \
	dialogues \
	multifilters \
	nostream \
	notablejoin \
	projection \
	projection_with_filter \
	schema_org \
	undefined_filter \
	anything_else \
	multiwoz \
	$(NULL)

target_pruning_size ?= 200
minibatch_size ?= 500
target_size ?= 1
subdatasets ?= 6
subdataset_ids = $(shell seq 1 $(subdatasets))
max_turns ?= 6
max_depth ?= 9
synthetic_expand_factor ?= 1

generate_flags = $(foreach v,$(synthetic_flags),--set-flag $(v)) --target-pruning-size $(target_pruning_size) --max-turns $(max_turns) --maxdepth $(max_depth)
custom_gen_flags ?=

schema_deps = $(experiment)/schema.tt $(experiment)/entities.json
template_deps = \
	$(geniedir)/languages-dist/thingtalk/*.js \
	$(geniedir)/languages-dist/thingtalk/en/*.js \
	$(geniedir)/languages-dist/thingtalk/en/dlg/*.js

evalflags ?=

all: datadir

.PHONY: all evaluate
.SECONDARY:

emptydataset.tt:
	echo 'dataset @empty {}' > $@

$(experiment)/synthetic-%.txt : $(schema_deps) $(dataset_file) $(template_deps)
	$(genie) generate-dialogs \
	  --locale en-US --target-language thingtalk \
	  --policy $(geniedir)/languages-dist/$(template_file) \
	  --thingpedia $(experiment)/schema.tt --entities $(experiment)/entities.json --dataset $(dataset_file) \
	  -o $@.tmp -f txt $(generate_flags) --debug=1 $(custom_gen_flags) --random-seed $@ \
	  -n $(target_size) -B $(minibatch_size)
	mv $@.tmp $@

$(experiment)/synthetic.txt: $(foreach v,$(subdataset_ids),$(experiment)/synthetic-$(v).txt)
	cat $^ > $@

$(experiment)/synthetic-%.user.tsv : $(experiment)/synthetic-%.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --deduplicate \
	  --thingpedia $(experiment)/schema.tt --side user --flags S --id-prefix $*: \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/synthetic.user.tsv: $(foreach v,$(subdataset_ids),$(experiment)/synthetic-$(v).user.tsv)
	$(genie) deduplicate --contextual -o $@ $^

$(experiment)/synthetic-%.agent.tsv : $(experiment)/synthetic-%.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --deduplicate \
	  --thingpedia $(experiment)/schema.tt --side agent --flags S --id-prefix $*: \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/synthetic.agent.tsv: $(foreach v,$(subdataset_ids),$(experiment)/synthetic-$(v).agent.tsv)
	$(genie) deduplicate --contextual -o $@ $^

$(experiment)/augmented.user.tsv : $(experiment)/synthetic.user.tsv $($(experiment)_paraphrase_user) shared-parameter-datasets.tsv
	$(genie) augment -o $@.tmp \
	  --locale en-US --target-language thingtalk --contextual \
	  --thingpedia $(experiment)/schema.tt --parameter-datasets shared-parameter-datasets.tsv \
	  --synthetic-expand-factor $(synthetic_expand_factor) --quoted-paraphrasing-expand-factor 60 --no-quote-paraphrasing-expand-factor 20 --quoted-fraction 0.0 \
	  --debug $($(experiment)_paraphrase_user) $< --parallelize $(parallel)
	mv $@.tmp $@

$(experiment)/augmented.agent.tsv : $(experiment)/synthetic.agent.tsv $($(experiment)_paraphrase_agent) shared-parameter-datasets.tsv
	$(genie) augment -o $@.tmp \
	  --locale en-US --target-language thingtalk --contextual \
	  --thingpedia $(experiment)/schema.tt --parameter-datasets shared-parameter-datasets.tsv \
	  --synthetic-expand-factor $(synthetic_expand_factor) --quoted-paraphrasing-expand-factor 60 --no-quote-paraphrasing-expand-factor 20 --quoted-fraction 0.0 \
	  --debug $($(experiment)_paraphrase_agent) $< --parallelize $(parallel)
	mv $@.tmp $@

datadir/agent: $(experiment)/augmented.agent.tsv $(experiment)/eval/agent.tsv
	mkdir -p $@
	cp $(experiment)/synthetic.agent.tsv $@/
	if test $$(cat $(experiment)/eval/agent.tsv | wc -l) = 0 ; then \
	  $(genie) split-train-eval --train $@/train.tsv --eval $@/eval.tsv \
	    --eval-probability 0.1 --split-strategy sentence \
	    --contextual --eval-on-synthetic $(experiment)/augmented.agent.tsv ; \
	else \
	  cp $(experiment)/augmented.agent.tsv $@/train.tsv ; \
	  cp $(experiment)/eval/agent.tsv $@/eval.tsv ; \
	fi
	touch $@

datadir/nlg: $(experiment)/synthetic.agent.tsv $(experiment)/eval/agent.tsv
	mkdir -p $@
	if test $$(cat $(experiment)/eval/agent.tsv | wc -l) = 0 ; then \
	  $(genie) split-train-eval --train $@/train.tsv --eval $@/eval.tsv \
	    --eval-probability 0.1 --split-strategy raw-sentence \
	    --contextual --eval-on-synthetic $(experiment)/synthetic.agent.tsv ; \
	else \
	  cp $(experiment)/synthetic.agent.tsv $@/train.tsv ; \
	  cp $(experiment)/eval/agent.tsv $@/eval.tsv ; \
	fi
	touch $@

datadir/user: $(experiment)/augmented.user.tsv $(experiment)/eval/user.tsv
	mkdir -p $@
	cp $(experiment)/synthetic.user.tsv $@/
	if test $$(cat $(experiment)/eval/user.tsv | wc -l) = 0 ; then \
	  $(genie) split-train-eval --train $@/train.tsv --eval $@/eval.tsv \
	    --eval-probability 0.1 --split-strategy sentence \
	    --contextual --eval-on-synthetic $(experiment)/augmented.user.tsv ; \
	else \
	  cp $(experiment)/augmented.user.tsv $@/train.tsv ; \
	  cp $(experiment)/eval/user.tsv $@/eval.tsv ; \
	fi
	touch $@

datadir/fewshot: $(experiment)/eval_fewshot/user.tsv $(experiment)/eval_fewshot/agent.tsv $(experiment)/eval_fewshot/train.user.tsv $(experiment)/eval_fewshot/train.agent.tsv
	mkdir -p $@/user $@/agent
	cp $(experiment)/eval_fewshot/user.tsv $@/user/eval.tsv
	cp $(experiment)/eval_fewshot/train.user.tsv $@/user/train.tsv
	cp $(experiment)/eval_fewshot/agent.tsv $@/agent/eval.tsv
	cp $(experiment)/eval_fewshot/train.agent.tsv $@/agent/train.tsv
	touch $@

datadir: datadir/user datadir/agent datadir/nlg datadir/fewshot $(foreach v,$(subdataset_ids),$(experiment)/synthetic-$(v).txt)
	cat $(experiment)/synthetic-*.txt > $@/synthetic.txt
	$(genie) measure-training-set $@ > $@/stats
	touch $@

datadir/auto: $(experiment)/eval_auto_all/user.tsv $(experiment)/train_auto_all/user.tsv
	mkdir -p $@
	cp $(experiment)/train_auto_all/user.tsv $@/train.tsv
	cp $(experiment)/eval_auto_all/user.tsv $@/eval.tsv
	touch $@

$(experiment)/train_auto_selftrain/annotated.txt : train_dials.json $(experiment)/schema.tt $(experiment)/database-map.tsv shared-parameter-datasets.tsv
	mkdir -p "$(experiment)/train_auto_selftrain"
	$(genie) auto-annotate-multiwoz \
	  -o $@.tmp \
	  --user-nlu-server "file://$(abspath $(experiment)/models/nlu-user)" --agent-nlu-server "file://$(abspath $(experiment)/models/nlu-agent)" \
	  --thingpedia "$(experiment)/schema.tt" --database-file "$(experiment)/database-map.tsv" \
	  --parameter-datasets shared-parameter-datasets.tsv \
	  $< --no-use-existing $(auto_annotate_options)
	mv $@.tmp $@

datadir/selftrain: $(experiment)/eval_fewshot/user.tsv $(experiment)/train_auto_selftrain/user.tsv
	mkdir -p $@
	cp $(experiment)/train_auto_selftrain/user.tsv $@/train.tsv
	cp $(experiment)/eval_fewshot/user.tsv $@/eval.tsv
	touch $@

clean:
	for exp in $(all_experiments) ; do \
		rm -rf $$exp/synthetic* $$exp/everything* ; \
	done

$(experiment)/%/agent.tsv : $(experiment)/%/annotated.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --no-tokenized \
	  --thingpedia $(experiment)/schema.tt --side agent --flags E \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/%/user.tsv : $(experiment)/%/annotated.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --no-tokenized \
	  --thingpedia $(experiment)/schema.tt --side user \
	  $(if $(findstring train,$*),--ignore-errors,--flags E) \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/%/train.user.tsv : $(experiment)/%/train.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --no-tokenized \
	  --thingpedia $(experiment)/schema.tt --side user \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/%/train.agent.tsv : $(experiment)/%/train.txt $(schema_deps)
	$(genie) dialog-to-contextual \
	  --locale en-US --target-language thingtalk --no-tokenized \
	  --thingpedia $(experiment)/schema.tt --side agent \
	  -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/%/error-analysis.txt : $(experiment)/%/annotated.txt $(schema_deps) $(geniedir)/tool/analyze-dialogue-annotations.ts $(experiment)/database-map.tsv shared-parameter-datasets.tsv
	$(genie) analyze-dialogue-annotations \
	  --locale en-US --thingpedia $(experiment)/schema.tt \
	  --database-file $(experiment)/database-map.tsv \
	  --parameter-datasets shared-parameter-datasets.tsv \
	  --mode synthesis -o $@.tmp $<
	mv $@.tmp $@

$(experiment)/%/feature-analysis.txt : $(experiment)/%/annotated.txt $(schema_deps) $(geniedir)/tool/analyze-dialogue-annotations.ts $(experiment)/database-map.tsv shared-parameter-datasets.tsv
	$(genie) analyze-dialogue-annotations \
	  --locale en-US --thingpedia $(experiment)/schema.tt \
	  --database-file $(experiment)/database-map.tsv \
	  --parameter-datasets shared-parameter-datasets.tsv \
	  --mode features -o $@.tmp $<
	mv $@.tmp $@

evaluate: $(foreach set,$(eval_set),$(experiment)/$(set)/$(model).dialogue.results) $(foreach set,$(eval_set),$(experiment)/$(set)/$(model).nlu.results)
	cat $(foreach set,$(eval_set),$(experiment)/$(set)/$(model).dialogue.results)

$(experiment)/%/$(model).nlu.results: $(experiment)/models/$(model)/best.pth $(experiment)/%/user.tsv $(experiment)/schema.tt
	mkdir -p $(experiment)/$*/$(dir $(model))
	$(genie) evaluate-server --contextual \
	  --url "file://$(abspath $(dir $<))" \
	  --thingpedia $(experiment)/schema.tt \
	  $(experiment)/$*/user.tsv \
	  --debug --csv-prefix $* --csv \
	  --complexity-metric turn_number --max-complexity 5 \
	  $(evalflags) \
	  -o $@.tmp > $(experiment)/$*/$(model).nlu.debug
	mv $@.tmp $@

$(experiment)/%/$(model).dialogue.results: $(experiment)/models/$(model)/best.pth $(experiment)/%/annotated.txt $(experiment)/schema.tt
	mkdir -p $(experiment)/$*/$(dir $(model))
	$(genie) evaluate-dialog  \
	  --url "file://$(abspath $(dir $<))" \
	  --thingpedia $(experiment)/schema.tt \
	  --target-language thingtalk \
	  $(experiment)/$*/annotated.txt \
	  --database-file $(experiment)/database-map.tsv \
	  --parameter-datasets shared-parameter-datasets.tsv \
	  --debug --csv-prefix $* --csv $(evalflags) \
	  -o $@.tmp > $(experiment)/$*/$(model).dialogue.debug
	mv $@.tmp $@
