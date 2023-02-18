# Evaluation Scripts for "A few-shot semantic parser for Wizard-of-Oz dialogues with the precise ThingTalk representation"

This repository contains the data and evaluation scripts for the paper "A few-shot semantic parser for Wizard-of-Oz dialogues with the precise ThingTalk representation", which appeared in Findings of ACL 2022.

## Setup

1. Install [genie-toolkit](https://github.com/stanford-oval/genie-toolkit) at version 807d75e3c8292d61cc339568b47b731dcdc4b7ea
2. Edit `Makefile` to set `geniedir` to point to the installation directory for genie-toolkit
3. Install [genienlp](https://github.com/stanford-oval/genienlp) at version a83038aeab124007dba98b34d0dec5f817b63392
4. Make sure that the `genienlp` command is available in the path.

## Data

This repository only contains the evaluation data.
The training data for the paper, including the synthesized data, is available at https://drive.google.com/file/d/1ZmCodLiSGHUuXwH7P62nzJDCC5RkH3yv/view?usp=sharing

The above link contains:
- `base`: dataset containing only synthesized data for training
- `base/fewshot`: few-shot manually annotated data
- `with-paraphrase`: dataset containing synthesized and automatically paraphrase data
- `selftrain`: self-trained dataset
- `test`: evaluation data (same as this repository)

Each training data folder contains `user` and `agent`, to train a model to interpret user utterances and to interpret agent utterances respectively. The latter is used to prepare self-train data.

## Training

Unpack the appropriate data folder into `dataset/almond`.

A new model can be trained with:
```
genienlp train \
          --data "dataset" \
          --save "multidomain/models/${model_name}" \
          --train_tasks ${task_name} \
          --preserve_case \
          --exist_ok \
          --train_languages en \
          --eval_languages en \
          --eval_set_name eval \
          ${hyperparams}
```
where `${task_name}` is:
- `almond_dialogue_nlu` for a model that interprets user utterances
- `almond_dialogue_nlu_agent` for a model that interprets agent utterances

Set `${model_name}` to a custom identifier of the model.

Hyperparams set for our experiments are:
```
--model TransformerSeq2Seq --pretrained_model facebook/bart-large --eval_set_name eval --train_batch_tokens 2500 --val_batch_size 4000 --preprocess_special_tokens --gradient_accumulation_steps 20 --warmup 40 --lr_multiply 0.01
```

## Evaluation

After training, a model can be evaluated as:
```
make evaluate model=${model_name}
```

Set `eval_set=eval` to only evaluate on the dev set, or `eval_set=test` to only evaluate on the test set.

Results are saved in `multidomain/{eval,test}/${model_name}.dialogue.results` and also printed on the terminal.
The results file is a CSV line with:

- evaluation set
- number of evaluation dialogues
- number of evaluation turns
- % of completely correct dialogues (exact match, slot only)
- % of accuracy first turns (exact match, slot only)
- turn by turn accuracy (exact match, slot only) - corresponds to **turn by turn** in the paper
- accuracy up to first error (exact match, slot only) - corresponds to **dialogue accuracy** in the paper
- average turn at which the first error occurs (exact match, slot only)

## Generating a new dataset

A new fresh synthesized dataset can be generated with
```
make -j datadir
```

This can take a few hours and requires a lot of RAM. Adjust `memsize` in the Makefile if OOM occurs.

The output directory structure is the same as the `base` folder in the data release, but additional intermediate files are generated. These can be discarded prior to training.

## Selftrain

1. Download `train_dials.json` from the original MultiWOZ 2.1 release.
2. Prepare the models as `multidomain/models/nlu-user` and `multidomain/models/nlu-agent`
3. Run `make datadir/selftrain`

## Citation

If you use the dataset or scripts in this repository, please cite:
```
@inproceedings{campagna-etal-2022-shot,
    title = "A Few-Shot Semantic Parser for {W}izard-of-{O}z Dialogues with the Precise {T}hing{T}alk Representation",
    author = "Campagna, Giovanni  and
      Semnani, Sina  and
      Kearns, Ryan  and
      Koba Sato, Lucas Jun  and
      Xu, Silei  and
      Lam, Monica",
    booktitle = "Findings of the Association for Computational Linguistics: ACL 2022",
    month = may,
    year = "2022",
    address = "Dublin, Ireland",
    publisher = "Association for Computational Linguistics",
    url = "https://aclanthology.org/2022.findings-acl.317",
    doi = "10.18653/v1/2022.findings-acl.317",
    pages = "4021--4034",
}
```

Additionaly, human-written dialogue data originally comes from MultiWOZ 2.1:
```
@article{eric2019multiwoz,
  title={MultiWOZ 2.1: A consolidated multi-domain dialogue dataset with state corrections and state tracking baselines},
  author={Eric, Mihail and Goel, Rahul and Paul, Shachi and Kumar, Adarsh and Sethi, Abhishek and Ku, Peter and Goyal, Anuj Kumar and Agarwal, Sanchit and Gao, Shuyang and Hakkani-Tur, Dilek},
  journal={arXiv preprint arXiv:1907.01669},
  year={2019}
}
```

## Help and Support

In case of any issue with the above, please open an issue in this repository or contact the authors via email.
