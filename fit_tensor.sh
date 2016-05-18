#! /bin/sh

usage_exit() {
      cat <<EOF

  Fit the tensor to diffusion data

  Example Usage:
  
    fit_tensor.sh -k out/mc_unwarped_raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M brain_mask.nii.gz

    Required:
    -k <img>    : DTI 4D data
    -b <bvals.txt> : a text file containing a list of b-values
    -r <bvecs.txt> : a text file containing a list of b-vectors
    -M <img>       : mask file for diffusion images 

    Option: 
    -s <number>       : noise level for restore
                        (default: calculate based on linear tensor residuals)
    -f                : use dtifit instead of RESTORE in camino 
    -o <dir>          : output directory
    -F                : fast mode for testing (minimal iterations)
    -E                : don't run the commands, just echo them

EOF
    exit 1;
}

#---------variables and functions---------#
method=restore
sigma=CALCULATE
data="PARSE_ERROR_data"
tmpdir=temp-fit_tensor              
LF=$tmpdir/fit_tensor.log           # default log filename
bval="PARSE_ERROR_bval"             # b-values file (in FSL format)
bvec="PARSE_ERROR_vec"              # b-vectors file (in FSL format)
mask="PARSE_ERROR_mask"             # brain mask file 
outdir=.                            # output directory
generate_report=y                   # generate a report 
mode=normal
reportdir=$tmpdir/report            # directory for html report
scriptdir=`dirname $0`

#------------- Parse Parameters  --------------------#
[ "$4" = "" ] && usage_exit

while getopts k:b:r:M:o:s:FfE OPT
 do
 case "$OPT" in 
   "k" ) data="$OPTARG";; 
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;
   "M" ) mask="$OPTARG";;   
   "f" ) method=fsl;;
   "o" ) outdir="$OPTARG";;   
   "s" ) sigma="$OPTARG";;
   "F" ) fast_testing=y;;
   "E" ) mode=echo;;
     * ) usage_exit;;
 esac
done;


#------------- Utility functions ----------------#

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

 if [ "$R" = "1" ] && [ "$mode" != "echo" ] ; then 
  eval $cmd | tee -a $LF    # workaround for redirects and pipes. Stderr is not redirected to logfile
 fi

 if [ "$E" != "1" ] && [ "$mode" != "echo" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. read the output and the error messages to the log file
 fi

 echo  | tee -a $LF         # write an empty line to the console and log file
}

error_exit (){      
    echo "$1" >&2   # Send message to stderr
    echo "$1" >> $LF # send message to log file
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


#------------- Setting things up ----------------#

## make output directory
mkdir -p $outdir


## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF

echo "Logfife for command: " >> $LF
echo $0 $@ >> $LF
echo "Run on " `date` "by user " $USER " on machine " `hostname`  >> $LF
echo "" >> $LF

#------------- Check dependencies ----------------#

command -v fsl > /dev/null 2>&1 || { error_exit "ERROR: FSL required, but not found (http://fsl.fmrib.ox.ac.uk/fsl). Aborting."; } 

if [ "$method" = "restore" ] ; then
  command -v modelfit > /dev/null 2>&1 || { error_exit "ERROR: CAMINO required for RESTORE, but not found (http://camino.cs.ucl.ac.uk). Aborting."; } 
fi

#------------- verifying inputs ----------------#

if [ `test_varimg $data` -eq 0 ]; then
 error_exit "ERROR: cannot find image for 4D raw diffusion data: $data"
else
  dtidim4=`fslval $data dim4`
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find mask image: $mask" 
fi

if [ `test_varfile $bvec` -eq 0 ]; then error_exit "ERROR: $bvec is not a valid bvec file"; fi

bvecl=`cat $bvec | awk 'END{print NR}'`
bvecw=`cat $bvec | wc -w` 
if [ $bvecl != 3 ]; then error_exit "ERROR: bvecs file contains $bvecl lines, it should be 3 lines, each for x, y, z"; fi
if [ "$bvecw" != "`expr 3 \* $dtidim4`" ]; then error_exit "ERROR: bvecs file contains $bvecw words, it should be 3 x $dtidim4 = `expr 3 \* $dtidim4` words"; fi

if [ `test_varfile $bval` -eq 0 ]; then error_exit "ERROR: $bval is not a valid bvals file"; fi

bvall=`cat $bval | awk 'END{print NR}'`; bvalw=`cat $bval | wc -w`
if [ $bvall != 1 ]; then error_exit "ERROR: bvals file contains $bvall lines, it should be 1 lines"; fi
if [ $bvalw != $dtidim4 ]; then error_exit "ERROR: bvalc file contains $bvalw words, it should be $dtidim4 words"; fi 




#-------------- fitting the tensor ------------------#

dtidim4=`fslval $data dim4`
s0_count=`cat $bval | tr ' ' '\n' | grep -c ^0`
dwi_count=`expr $dtidim4 - $s0_count`
total_count=`echo $dwi_count + $s0_count | bc`

if [ "$fast_testing" = "y" ]; then
  method=fsl
fi

if [ "$method" = "fsl" ] ; then
 T dtifit -k $data -o $tmpdir/dti -b $bval -r $bvec -m $mask --sse --save_tensor --wls 
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

 ## do the fitting.

 T modelfit -inputfile $data -schemefile $tmpdir/scheme.txt -model restore -sigma $sigma -outliermap $tmpdir/outlier_map.Bbyte -bgmask $mask -outputfile $tmpdir/restore_tensor.Bfloat

 ## rename and convert files

 T -r "cat $tmpdir/restore_tensor.Bfloat | fa -header $data -outputfile $tmpdir/dti_FA.nii.gz"
 T -r "cat $tmpdir/restore_tensor.Bfloat | md -header $data -outputfile $tmpdir/dti_MD.nii.gz"

 T -r "cat $tmpdir/restore_tensor.Bfloat | voxel2image -components 8 -header $data -outputroot $tmpdir/dti_restore_tensor_"

 T -r "cat $tmpdir/outlier_map.Bbyte | voxel2image -inputdatatype byte -components $dwi_count -header $data -outputroot $tmpdir/dti_outlier_map_"

 # T -r "cat $tmpdir/residual_map.Bdouble | voxel2image -inputdatatype double -components $total_count -header $data -outputroot $tmpdir/residual_map_"

 T -r "cat $tmpdir/restore_tensor.Bfloat | dteig | voxel2image -components 12 -inputdatatype double -header $data -outputroot $tmpdir/dti_eigsys_ "

 # scale tensor, eigenvalues, and MD by 10^6 so that the units are consistent with FSL
 for s in $tmpdir/dti_restore_tensor_000{3,4,5,6,7,8}.nii.gz $tmpdir/dti_eigsys_000{1,5,9}.nii.gz $tmpdir/dti_MD.nii.gz ; do
  T fslmaths $s -mul 1e6 $s
 done

 T imcp $tmpdir/dti_restore_tensor_0001.nii.gz $tmpdir/dti_exit_code
 T imcp $tmpdir/dti_restore_tensor_0002.nii.gz $tmpdir/dti_log_s0
 T imcp $tmpdir/dti_restore_tensor_0003.nii.gz $tmpdir/dti_dxx
 T imcp $tmpdir/dti_restore_tensor_0004.nii.gz $tmpdir/dti_dxy
 T imcp $tmpdir/dti_restore_tensor_0005.nii.gz $tmpdir/dti_dxz
 T imcp $tmpdir/dti_restore_tensor_0006.nii.gz $tmpdir/dti_dyy
 T imcp $tmpdir/dti_restore_tensor_0007.nii.gz $tmpdir/dti_dyz
 T imcp $tmpdir/dti_restore_tensor_0008.nii.gz $tmpdir/dti_dzz

 T fslmaths $tmpdir/dti_log_s0 -exp $tmpdir/dti_S0

 T imcp $tmpdir/dti_eigsys_0001.nii.gz $tmpdir/dti_L1
 T imcp $tmpdir/dti_eigsys_0005.nii.gz $tmpdir/dti_L2
 T imcp $tmpdir/dti_eigsys_0009.nii.gz $tmpdir/dti_L3

 T fslmerge -t $tmpdir/dti_V1 $tmpdir/dti_eigsys_0002.nii.gz $tmpdir/dti_eigsys_0003.nii.gz $tmpdir/dti_eigsys_0004.nii.gz
 T fslmerge -t $tmpdir/dti_V2 $tmpdir/dti_eigsys_0006.nii.gz $tmpdir/dti_eigsys_0007.nii.gz $tmpdir/dti_eigsys_0008.nii.gz
 T fslmerge -t $tmpdir/dti_V3 $tmpdir/dti_eigsys_0010.nii.gz $tmpdir/dti_eigsys_0011.nii.gz $tmpdir/dti_eigsys_0012.nii.gz

 T fslmerge -t $tmpdir/dti_tensor $tmpdir/dti_dxx $tmpdir/dti_dxy $tmpdir/dti_dxz $tmpdir/dti_dyy $tmpdir/dti_dyz $tmpdir/dti_dzz


 T fslmaths $tmpdir/dti_exit_code.nii.gz -sub 1000 -thr 0 $tmpdir/dti_outlier_count.nii.gz


 # pad the outlier map with mask images so that it can be overlaid on the diffusion images (same number of volumes)
 T imcp $mask $tmpdir/outlier_pad
 for i in `seq 2 $s0_count`; do
  T fslmerge -t $tmpdir/outlier_pad.nii.gz $mask $tmpdir/outlier_pad.nii.gz
 done

 T fslmerge -t $tmpdir/dti_outlier_map.nii.gz $tmpdir/outlier_pad.nii.gz $tmpdir/dti_outlier_map_*.nii.gz
 # T fslmerge -t $tmpdir/residual_map.nii.gz $mask $tmpdir/residual_map_*.nii.gz

 ## clean up
 T rm $tmpdir/dti_outlier_map_????.nii.gz
 # T rm $tmpdir/residual_map_????.nii.gz
 T rm $tmpdir/dti_restore_tensor_????.nii.gz
 T rm $tmpdir/dti_eigsys_????.nii.gz

 ## copy restore-specific files to output directory
 T imcp $tmpdir/dti_outlier_count.nii.gz $tmpdir/dti_outlier_map.nii.gz $outdir/

fi

## copy files to output directory
 T imcp $tmpdir/dti_FA $tmpdir/dti_MD $tmpdir/dti_tensor $tmpdir/dti_L1 $tmpdir/dti_L2 $tmpdir/dti_L3 $tmpdir/dti_V1 $tmpdir/dti_V2 $tmpdir/dti_V3 $tmpdir/dti_S0 $outdir/


if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/fit_tensor_report.sh -t $tmpdir -r $reportdir -o $outdir -k $data -m $method -n $s0_count
fi

T cp $reportdir/*.html $outdir/
