#!/bin/bash

# make animated gifs out of a 4d image stack
#

# Takes 1 input (input 4d image )
# Usages: image_to_movie.sh <input 4D nifti file> 

#set -x

input=$1

#output=${input%%.*}_movie.gif
output=$2

tmpdir=`mktemp -d`
SCRIPTDIR=`dirname $0`

echo splitting images
fslsplit $input $tmpdir/volume_ -t

echo making individual gifs
for s in $tmpdir/volume*.nii.gz ; do 
  $SCRIPTDIR/image_to_gif.sh $s ${s}.gif
done

echo making the movie
whirlgif -o $output -loop -time 10 $tmpdir/volume*.nii.gz.gif

rm -rf $tmpdir