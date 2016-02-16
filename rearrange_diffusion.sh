#!/bin/bash

# rearranges a diffusion dataset according to a given vector
# rearrange_diffusion.sh download_diffusion.nii.gz download_bvals.txt download_bvecs.txt rearranged 1 15 `seq 2 14` `seq 16 30`

inputfile=$1
bvalsfile=$2
bvecsfile=$3
output_basename=$4

temp_basename=temp-permute_diffusion
remove_temp_files=y

shift
shift
shift
shift

perm_vector=$@

rm -f ${output_basename}_diffusion.nii.gz
rm -f ${output_basename}_bvecs.txt
rm -f ${output_basename}_bvals.txt
rm -f ${temp_basename}_*

touch ${temp_basename}_bvecs_{x,y,z}.txt
touch ${temp_basename}_bvals.txt

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
# echo "fslmerge -t ${output_basename}_diffusion.nii.gz $imagelist"
fslmerge -t ${output_basename}_diffusion.nii.gz $imagelist

echo `cat ${temp_basename}_bvals.txt | tr '\n' ' '` > ${output_basename}_bvals.txt

echo `cat ${temp_basename}_bvecs_x.txt | tr '\n' ' '` > ${output_basename}_bvecs.txt
echo `cat ${temp_basename}_bvecs_y.txt | tr '\n' ' '` >> ${output_basename}_bvecs.txt
echo `cat ${temp_basename}_bvecs_z.txt | tr '\n' ' '` >> ${output_basename}_bvecs.txt

if [ "$remove_temp_files" = "y" ]; then
 rm -f ${temp_basename}_*
fi
