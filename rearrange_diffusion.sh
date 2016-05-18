#!/bin/bash

usage_exit() {
      cat <<EOF

  rearrange diffusion data, b-values, AND b-vectors according to an sequence of integers

   Usage:
     rearrange_diffusion.sh <4d image> <bvals> <bvecs> <output basename> <permutation vector>
 
   Example: (moves image #15 to the second position):
     rearrange_diffusion.sh download_diffusion.nii.gz download_bvals.txt download_bvecs.txt rearranged 1 15 \`seq 2 14\` \`seq 16 30\`

EOF
    exit 1;
}

#------------- parsing parameters ----------------#
if [ "$6" = "" ]; then usage_exit; fi  #show help message if fewer than six args

remove_temp_files=y

inputfile=$1
bvalsfile=$2
bvecsfile=$3
output_basename=$4

temp_basename=temp-rearrange_diffusion

shift
shift
shift
shift

perm_vector=$@

#-------------- utility functions ----------------3

error_exit (){      
    echo "$1" > &2   # Send message to stderr
    exit "${2:-1}"  # Return a code specified by $2 or 1 by default.
}

test_varimg (){   # test if a string is a valid image file
    var=$1
    if [ "x$var" = "x" ]; then test=0; else  test=`imtest $1`; fi
    echo $test
}

test_varfile (){  # test if a string is a valid file
    var=$1
    if [ "x$var" = "x" ]; then test=0 ; elif [ ! -f $var ]; then test=0; else test=1; fi
    echo $test
}

#------------- verify inputs  ------------------#

if [ `test_varimg $inputfile` -eq 0 ]; then
 error_exit "ERROR: cannot find image for 4D diffusion data: $inputfile"
else
  dtidim4=`fslval $inputfile dim4`
fi

if [ `test_varfile $bvecsfile` -eq 0 ]; then error_exit "ERROR: $bvecsfile is not a valid b-vector file"; fi

bvecl=`cat $bvecsfile | awk 'END{print NR}'`
bvecw=`cat $bvecsfile | wc -w` 
if [ $bvecl != 3 ]; then error_exit "ERROR: bvecs file contains $bvecl lines, it should be 3 lines, each for x, y, z"; fi
if [ "$bvecw" != "`expr 3 \* $dtidim4`" ]; then error_exit "ERROR: bvecs file contains $bvecw words, it should be 3 x $dtidim4 = `expr 3 \* $dtidim4` words"; fi

if [ `test_varfile $bvalsfile` -eq 0 ]; then error_exit "ERROR: $bvalsfile is not a valid bvals file"; fi

bvall=`cat $bvalsfile | awk 'END{print NR}'`; bvalw=`cat $bvalsfile | wc -w`
if [ $bvall != 1 ]; then error_exit "ERROR: bvals file contains $bvall lines, it should be 1 lines"; fi
if [ $bvalw != $dtidim4 ]; then error_exit "ERROR: bvalc file contains $bvalw words, it should be $dtidim4 words"; fi 



#------------- Setting things up ----------------#

rm -f ${output_basename}_diffusion.nii.gz
rm -f ${output_basename}_bvecs.txt
rm -f ${output_basename}_bvals.txt
rm -f ${temp_basename}_*

touch ${temp_basename}_bvecs_{x,y,z}.txt
touch ${temp_basename}_bvals.txt

#------------- do the rearrangement --------------#

echo splitting images
fslsplit $inputfile ${temp_basename}_ -t

for i in $perm_vector; do

 #zero-indexed
 izi=`expr $i - 1`

 # zero-padded zero-indexed
 izpzi=`zeropad $izi 4`
 
 imagelist=`echo $imagelist ${temp_basename}_${izpzi}.nii.gz`

 cat $bvalsfile | awk -v n=$i '{print $n}' >> ${temp_basename}_bvals.txt

 cat $bvecsfile | awk -v n=$i '{if (NR == 1) {print $n}}' >> ${temp_basename}_bvecs_x.txt
 cat $bvecsfile | awk -v n=$i '{if (NR == 2) {print $n}}' >> ${temp_basename}_bvecs_y.txt
 cat $bvecsfile | awk -v n=$i '{if (NR == 3) {print $n}}' >> ${temp_basename}_bvecs_z.txt

done
 
echo merging images

fslmerge -t ${output_basename}_diffusion.nii.gz $imagelist

echo `cat ${temp_basename}_bvals.txt | tr '\n' ' '` > ${output_basename}_bvals.txt

echo `cat ${temp_basename}_bvecs_x.txt | tr '\n' ' '` > ${output_basename}_bvecs.txt
echo `cat ${temp_basename}_bvecs_y.txt | tr '\n' ' '` >> ${output_basename}_bvecs.txt
echo `cat ${temp_basename}_bvecs_z.txt | tr '\n' ' '` >> ${output_basename}_bvecs.txt


## Clean up
if [ "$remove_temp_files" = "y" ]; then
 rm -f ${temp_basename}_*
fi
