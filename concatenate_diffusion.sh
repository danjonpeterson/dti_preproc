#!/bin/bash

usage_exit() {
      cat <<EOF

  concatentates two runs of diffusion data, including the 4d images, bvals and bvecs

   Usage:
     concatenate_diffusion.sh <4d image #1> <bvals #1> <bvecs #1> <4d image #2> <bvals #2> <bvecs #2> <output basename> 
 
   Example:

     this command:
     concatenate_diffusion.sh diffusion_blipA.nii.gz bvals_blipA.txt bvecs_blipA.txt diffusion_blipP.nii.gz bvals_blipP.txt bvecs_blipP.txt merged

     creates files:
     merged_diffusion.nii.gz
     merged_bval.txt
     merged_bvec.txt  

EOF
    exit 1;
}

#------------- parsing parameters ----------------#
if [ "$6" = "" ]; then usage_exit; fi  #show help message if fewer than seven args

remove_temp_files=y

inputfile_A=$1
bvalsfile_A=$2
bvecsfile_A=$3

inputfile_B=$4
bvalsfile_B=$5
bvecsfile_B=$6

output_basename=$7

#-------------- utility functions ----------------#
error_exit (){      
    echo "$1" >&2   # Send message to stderr
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
if [ `test_varimg $inputfile_A` -eq 0 ]; then
 error_exit "ERROR: cannot find image for first 4D diffusion data: $inputfile_A"
else
  dtidim4_A=`fslval $inputfile_A dim4  | awk '{print $1}'`
fi

if [ `test_varfile $bvecsfile_A` -eq 0 ]; then error_exit "ERROR: first b-vector file $bvecsfile_A is not a valid b-vector file"; fi

bvecl_A=`cat $bvecsfile_A | awk 'END{print NR}'`
bvecw_A=`cat $bvecsfile_A | wc -w` 
if [ "$bvecl_A" != "3" ]; then error_exit "ERROR: first bvecs file contains $bvecl_A lines, it should be 3 lines, each for x, y, z"; fi
if [ "$bvecw_A" != "`expr 3 \* $dtidim4_A`" ]; then error_exit "ERROR: first bvecs file contains $bvecw_A words, it should be 3 x $dtidim4_A = `expr 3 \* $dtidim4_A` words"; fi

if [ `test_varfile $bvalsfile_A` -eq 0 ]; then error_exit "ERROR: first b-value file $bvalsfile_A is not a valid bvals file"; fi

bvall_A=`cat $bvalsfile_A | awk 'END{print NR}'`; bvalw_A=`cat $bvalsfile_A | wc -w`
if [ "$bvall_A" != "1" ]; then error_exit "ERROR: first bvals file contains $bvall_A lines, it should be 1 lines"; fi
if [ "$bvalw_A" != "$dtidim4_A" ]; then error_exit "ERROR: first bval file contains $bvalw_A words, it should be $dtidim4_A words"; fi 


if [ `test_varimg $inputfile_B` -eq 0 ]; then
 error_exit "ERROR: cannot find image for second 4D diffusion data: $inputfile_B"
else
  dtidim4_B=`fslval $inputfile_B dim4 | awk '{print $1}'`
fi

if [ `test_varfile $bvecsfile_B` -eq 0 ]; then error_exit "ERROR: second b-vector file $bvecsfile_B is not a valid b-vector file"; fi

bvecl_B=`cat $bvecsfile_B | awk 'END{print NR}'`
bvecw_B=`cat $bvecsfile_B | wc -w` 
if [ $bvecl_B != 3 ]; then error_exit "ERROR: second bvecs file contains $bvecl_B lines, it should be 3 lines, each for x, y, z"; fi
if [ "$bvecw_B" != "`expr 3 \* $dtidim4_B`" ]; then error_exit "ERROR: second bvecs file contains $bvecw_B words, it should be 3 x $dtidim4_B = `expr 3 \* $dtidim4_B` words"; fi

if [ `test_varfile $bvalsfile_B` -eq 0 ]; then error_exit "ERROR: second b-value file $bvalsfile_B is not a valid bvals file"; fi

bvall_B=`cat $bvalsfile_B | awk 'END{print NR}'`; bvalw_B=`cat $bvalsfile_B | wc -w`
if [ "$bvall_B" != "1" ]; then error_exit "ERROR: second bvals file contains $bvall_B lines, it should be 1 lines"; fi
if [ "$bvalw_B" != "$dtidim4_B" ]; then error_exit "ERROR: second bval file contains $bvalw_B words, it should be $dtidim4_B words"; fi 

if [ "x$output_basename" = "x" ]; then
	error_exit "ERROR: no output basename supplied"
fi

#------------- do the concatenation --------------#

fslmerge -t ${output_basename}_diffusion $inputfile_A $inputfile_B

#replace tabs from paste and double-spaces with single spaces
paste $bvalsfile_A $bvalsfile_B | tr '\t' ' ' | tr -s '  ' ' '  > ${output_basename}_bval.txt

paste $bvecsfile_A $bvecsfile_B | tr '\t' ' ' | tr -s '  ' ' '  > ${output_basename}_bvec.txt


