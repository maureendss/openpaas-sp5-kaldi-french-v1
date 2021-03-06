#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
#           2014  Guoguo Chen
# Apache 2.0

[ -f ./path.sh ] && . ./path.sh

# begin configuration section.
cmd=run.pl
stage=0
decode_mbr=true
reverse=false
word_ins_penalty=0.0,0.5,1.0
min_lmwt=9
max_lmwt=20
iter=final

#end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score.sh [--cmd (run.pl|queue.pl...)] <data-dir> <lang-dir|graph-dir> <decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --decode_mbr (true/false)       # maximum bayes risk decoding (confusion network)."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  echo "    --reverse (true/false)          # score with time reversed features "
  exit 1;
fi

data=$1
lang_or_graph=$2
dir=$3

symtab=$lang_or_graph/words.txt

for f in $symtab $dir/lat.1.gz $data/text; do
  [ ! -f $f ] && echo "score.sh: no such file $f" && exit 1;
done

mkdir -p $dir/scoring/log

cat $data/text | sed 's:<NOISE>::g' | sed 's:<SPOKEN_NOISE>::g' > $dir/scoring/test_filt.txt

for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/best_path.LMWT.$wip.log \
    lattice-scale --inv-acoustic-scale=LMWT "ark:gunzip -c $dir/lat.*.gz|" ark:- \| \
    lattice-add-penalty --word-ins-penalty=$wip ark:- ark:- \| \
    lattice-best-path --word-symbol-table=$symtab \
      ark:- ark,t:$dir/scoring/LMWT.$wip.tra || exit 1;
done

if $reverse; then
  for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
    for lmwt in `seq $min_lmwt $max_lmwt`; do
      mv $dir/scoring/$lmwt.$wip.tra $dir/scoring/$lmwt.$wip.tra.orig
      awk '{ printf("%s ",$1); for(i=NF; i>1; i--){ printf("%s ",$i); } printf("\n"); }' \
        <$dir/scoring/$lmwt.$wip.tra.orig >$dir/scoring/$lmwt.$wip.tra
    done
  done
fi

[ ! -f $lang_or_graph/wordsa.txt ] && cat $lang_or_graph/words.txt | sed 's/([[:digit:]])//g' > $lang_or_graph/wordsa.txt
symtab=$lang_or_graph/wordsa.txt
# Note: the double level of quoting for the sed command
for wip in $(echo $word_ins_penalty | sed 's/,/ /g'); do
  $cmd LMWT=$min_lmwt:$max_lmwt $dir/scoring/log/score.LMWT.$wip.log \
    cat $dir/scoring/LMWT.$wip.tra \| \
    utils/int2sym.pl -f 2- $symtab \| sed 's:\<UNK\>::g' \| \
    compute-wer --text --mode=present \
    ark:$dir/scoring/test_filt.txt  ark,p:- ">&" $dir/wer_LMWT_$wip || exit 1;
done

exit 0;
