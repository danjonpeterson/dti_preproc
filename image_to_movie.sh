#!/bin/bash

# make animated gifs out of a 4d image stack
#

# Takes 1 input (input 4d image )
# Usages: image_to_movie.sh <input 4D nifti file> 

# set -x

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

if command -v whirlgif > /dev/null 2>&1 ; then
  whirlgif -o $output -loop -time 10 $tmpdir/volume*.nii.gz.gif
elif command -v gifsicle >  /dev/null 2>&1 ; then
  gifsicle -o $output -l -d 10 $tmpdir/volume*.nii.gz.gif
else
  echo "ERROR: neither whirlgif nor gifsicle installed" >&2
  exit 1
fi

rm -rf $tmpdir
