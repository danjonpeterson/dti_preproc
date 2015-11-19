#! /bin/sh

# example usage
# T fit_tensor.sh -k $outdir/resliced_$dti -b $bval -r $outdir/bvec_ecc -m $mask -o $outdir


#---------variables and functions---------#
method=restore
sigma=CALCULATE
data=DTI_64.nii.gz
tmpdir=temp-fit_tensor
LF=$tmpdir/fit_tensor.log
bvec=bvecs.txt
bval=bvals.txt
mask=MDW_brain_mask.nii.gz
outdir=.
dwi_count=64
s0_count=2
generate_report=y                   # generate a report 
reportdir=$tmpdir/report            # directory for html report
scriptdir=`dirname $0`

usage_exit() {
      cat <<EOF

  DTI calculation with correction for motion, eddy current distortion, B0 inhomogeneity distortion

  Version `echo "$VERSION" | awk '{print $1}'`

  Usage:
  
    $CMD -k <img> -b <bvals.txt> -r <bvecs.txt> [option]
      : calculates dti (w/o correction of B0 inhomogentity distortion)     
  
    -k <img>    : DTI 4D data
    -b <bvals.txt> : a text file containing a list of b-values
    -r <bvecs.txt> : a text file containing a list of b-vectors
  
    Option: 
    -m <img> : mask file for dti image 
    -p method (fsl,restore)
    -o output directory

EOF
    exit 1;
}

T () {

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 R=0
 if [ "$1" = "-r" ] ; then  # command has redirects and/or pipes
  E=1; R=1; shift           # don't run it again
 fi

 cmd="$*"

 echo "$cmd" | tee -a $LF   # read the command into the console, and the log file

 if [ "$R" = "1" ] ; then 
  eval $cmd | tee -a $LF    # workaround for redirects and pipes. Stderr is not redirected to logfile
 fi

 if [ "$E" != "1" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. read the output and the error messages to the log file
 fi

 echo  | tee -a $LF         # write an empty line to the console and log file
}

#------------- Parse Parameters  --------------------#
[ "$6" = "" ] && usage_exit

while getopts k:b:r:m:o:l4n OPT
 do
 case "$OPT" in 
   "k" ) data="$OPTARG";; 
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;
   "m" ) mask="$OPTARG";;   
   "o" ) outdir="$OPTARG";;   
     * ) usage_exit;;
 esac
done;


mkdir -p $outdir


## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF

## make output directory
mkdir $outdir

dtidim4=`fslval $data dim4`
s0_count=`cat $bval | tr ' ' '\n' | grep -c ^0`
dwi_count=`expr $dtidim4 - $s0_count`


if [ "$method" = "fsl" ] ; then
 T dtifit -k $data -o $tmpdir/dti_D -b bvals -r bvecs -m $tmpdir/ED_D_example_dti_brain_mask --sse
fi

if [ "$method" = "restore" ] ; then

 ## "T" breaks redirects to file
 T -r "fsl2scheme -bvecfile $bvec -bvalfile $bval > $tmpdir/scheme.txt"

 if [ "$sigma" = "CALCULATE" ] ; then   ## calculate sigma (std deviation of the noise) based on residuals from a weighted tensor fit
  T modelfit -inputfile $data -schemefile $tmpdir/scheme.txt -model ldt_wtd -noisemap $tmpdir/noise_map.Bdouble -bgmask $mask -outputfile $tmpdir/linear_tensor.Bfloat # -residualmap $tmpdir/residual_map.Bdouble

  ## grab noise map twice b/c of strange camino bug where the noise map is undersized
  T -r "cat $tmpdir/noise_map.Bdouble $tmpdir/noise_map.Bdouble | voxel2image -inputdatatype double -header $mask -outputroot $tmpdir/noise_map"

  ## square root of the variance of the noise is sigma
  T fslmaths $tmpdir/noise_map -sqrt $tmpdir/sigma_map
 
  ## get median of sigma map
  T fslstats $tmpdir/sigma_map -P 50
  sigma=`fslstats $tmpdir/sigma_map -P 50`
 fi 

 ## do the fitting
 T modelfit -inputfile $data -schemefile $tmpdir/scheme.txt -model restore -sigma $sigma -outliermap $tmpdir/outlier_map.Bbyte -bgmask $mask -outputfile $tmpdir/restore_tensor.Bfloat

 ## rename and convert files

 T -r "cat $tmpdir/restore_tensor.Bfloat | fa -header $data -outputfile $tmpdir/fa.nii.gz"
 T -r "cat $tmpdir/restore_tensor.Bfloat | md -header $data -outputfile $tmpdir/md.nii.gz"

 T -r "cat $tmpdir/restore_tensor.Bfloat | voxel2image -components 8 -header $data -outputroot $tmpdir/restore_tensor_"

 T -r "cat $tmpdir/outlier_map.Bbyte | voxel2image -inputdatatype byte -components $dwi_count -header $data -outputroot $tmpdir/outlier_map_"

total_count=`echo $dwi_count + $s0_count | bc`
# T -r "cat $tmpdir/residual_map.Bdouble | voxel2image -inputdatatype double -components $total_count -header $data -outputroot $tmpdir/residual_map_"

 T -r "cat $tmpdir/restore_tensor.Bfloat | dteig | voxel2image -components 12 -inputdatatype double -header $data -outputroot $tmpdir/eigsys_ "

 T imcp $tmpdir/restore_tensor_0001.nii.gz $tmpdir/exit_code
 T imcp $tmpdir/restore_tensor_0002.nii.gz $tmpdir/log_s0
 T imcp $tmpdir/restore_tensor_0003.nii.gz $tmpdir/dxx
 T imcp $tmpdir/restore_tensor_0004.nii.gz $tmpdir/dxy
 T imcp $tmpdir/restore_tensor_0005.nii.gz $tmpdir/dxz
 T imcp $tmpdir/restore_tensor_0006.nii.gz $tmpdir/dyy
 T imcp $tmpdir/restore_tensor_0007.nii.gz $tmpdir/dyz
 T imcp $tmpdir/restore_tensor_0008.nii.gz $tmpdir/dzz

 T imcp $tmpdir/eigsys_0001.nii.gz $tmpdir/L1
 T imcp $tmpdir/eigsys_0005.nii.gz $tmpdir/L2
 T imcp $tmpdir/eigsys_0009.nii.gz $tmpdir/L3

 T fslmerge -t $tmpdir/V1 $tmpdir/eigsys_0002.nii.gz $tmpdir/eigsys_0003.nii.gz $tmpdir/eigsys_0004.nii.gz
 T fslmerge -t $tmpdir/V2 $tmpdir/eigsys_0006.nii.gz $tmpdir/eigsys_0007.nii.gz $tmpdir/eigsys_0008.nii.gz
 T fslmerge -t $tmpdir/V3 $tmpdir/eigsys_0010.nii.gz $tmpdir/eigsys_0011.nii.gz $tmpdir/eigsys_0012.nii.gz

 T fslmerge -t $tmpdir/outlier_map.nii.gz $mask $tmpdir/outlier_map_*.nii.gz
# T fslmerge -t $tmpdir/residual_map.nii.gz $mask $tmpdir/residual_map_*.nii.gz

 ## clean up
 T rm $tmpdir/outlier_map_????.nii.gz
# T rm $tmpdir/residual_map_????.nii.gz
 T rm $tmpdir/restore_tensor_????.nii.gz
 T rm $tmpdir/eigsys_????.nii.gz

fi

## copy files to output directory
 T imcp $tmpdir/fa $tmpdir/md $tmpdir/dxx $tmpdir/dxy $tmpdir/dxz $tmpdir/dyy $tmpdir/dyz $tmpdir/dzz $tmpdir/L1 $tmpdir/L2 $tmpdir/L3 $tmpdir/V1 $tmpdir/V2 $tmpdir/V3 $outdir/

if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/fit_tensor_report.sh -t $tmpdir -r $reportdir -o $outdir -k $data -m $method
fi

cp $reportdir/*.html $outdir/
