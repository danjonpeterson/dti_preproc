#! /bin/sh

usage_exit() {
      cat <<EOF

  Preprocess DTI Data

    Examples:  

       for fieldmap-based unwarping:
      dti_preproc.sh -k raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M brain_mask.nii.gz \\
                     -f fieldmap_phase.nii.gz -m fieldmap_magnitude.nii.gz \\
                     -p fieldmap_magnitude_brain_mask -e 93.46 -t 0.567

       for blipup-blipbdown based unwarping:
      dti_preproc.sh -k raw_diffusion.nii.gz -b bval.txt -r bvec.txt -M brain_mask.nii.gz \\
                     -q acqparams.txt -i index.txt
  
    Required:
    -k <img>      : DTI 4D data
    -b <bval.txt> : a text file containing a list of b-values 
                    (fsl format - one line)
    -r <bvec.txt> : a text file containing a list of b-vectors 
                    (fsl format - three lines)
    -M <img>      : mask file 

    And either: 
    -f <img>      : fieldmap image (radian/sec)
    -m <img>      : fieldmap magnitude image
    -e <num>      : DTI TE (in ms)
    -t <num>      : DTI dwell time (in ms) 
    -p <img>      : mask for magnitude image

    Or:
    -q <file>     : acqpars file for topup
    -i <file>     : index file for topup

    Optional: 
    -c <file>     : topup configuration file

    -s <num>      : % signal loss threshold for B0 unwarping (default: 10)

    -o <dir>      : output directory (defaut: current working directory)
    -E            : don't run the commands, just echo them
    -F            : fast mode for testing (minimal iterations)

On github: https://github.com/danjonpeterson/dti_preproc.git

EOF
    exit 1;
}

#---------variables and defaults---------#
diffusion="PARSE_ERROR_dti"       # input raw diffusion file
dph="PARSE_ERROR_dph"             # fieldmap phase map
mag="PARSE_ERROR_mag"             # fieldmap magnitude image
bval="PARSE_ERROR_bval"           # b-values file (in FSL format)
bvec="PARSE_ERROR_vec"            # b-vectors file (in FSL format)
mask="PARSE_ERROR_mask"           # brain mask file
method="PARSE_ERROR_method"       # topup or fugue
SL=10                             # signal loss threshold
outdir=.                          # output directory
LF=dti_preprocess.log             # default log filename
mode=normal                       # run mode (normal,fast,echo)
scriptdir=`dirname $0`            # directory where dti_preproc scripts live



#------------- parsing parameters ----------------#
if [ "$6" = "" ]; then usage_exit; fi  #show help message if fewer than six args

while getopts k:b:r:M:f:m:e:t:p:q:i:c:s:o:EF OPT
 do
 case "$OPT" in 
   "k" ) diffusion="$OPTARG";; 
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;
   "M" ) mask="$OPTARG";; 
   "f" ) dph="$OPTARG"
         method="fugue";;
   "m" ) mag="$OPTARG";;
   "p" ) mag_mask="$OPTARG";;  
   "t" ) esp="$OPTARG";;  
   "e" ) te="$OPTARG";;
   "q" ) acqparams="$OPTARG"
         method="topup";;
   "i" ) index="$OPTARG";;
   "c" ) configfile="$OPTARG";;
   "s" ) SL="$OPTARG";;   
   "o" ) outdir="$OPTARG";;
   "E" ) mode=echo;;
   "F" ) mode=fast;;
    * )  usage_exit;;
 esac
done;

#------------- Utility functions ----------------#

T () {                      # main shell commands are run through here

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 cmd="$*"
 echo $* | tee -a $LF       # echo the command into the console, and the log file

 if [ "$E" != "1" ] && [ "$mode" != "echo" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. redirect the output into the log file. Stderr is not directed to the logfile
 fi

 echo | tee -a $LF         # write an empty line to the console and log file
}

error_exit (){      
    echo "$1" >&2   # Send message to stderr
    echo "$1" > $LF # send message to log file
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

## clear, then make the logfile
if [ -e $LF ]; then /bin/rm -f $LF ;fi
touch $LF

## make the output directory
T mkdir -p $outdir

if [ "$mode" = "echo" ]; then
  T -e "Running in echo mode - no actual processing done"
fi

#------------- verifying inputs ----------------#


if [ `test_varimg $diffusion` -eq 0 ]; then
 error_exit "ERROR: cannot find image for 4D raw diffusion data: $diffusion"
fi

if [ `test_varfile $bval` -eq 0 ]; then
 error_exit "ERROR: cannot find b-value file: $bval"
fi

if [ `test_varfile $bvec` -eq 0 ]; then
 error_exit "ERROR: cannot find b-vector file: $bvec"
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find mask image: $mask" 
fi

#------------- Motion and Distortion correction ----------------#
 
if [ "$method" = "topup" ]; then

  T -e "Unwarping distortions based on blipup-blipbdown data"

  T $scriptdir/unwarp_bupbdown.sh -k $diffusion -a $acqparams -M $mask -c $configfile -o $outdir
  
  T $scriptdir/motion_correct.sh -k $diffusion -b $bval -r $bvec -M $mask -m eddy_with_topup -i $index -a $acqparams -t temp-unwarp_bupbdown/topup_out -o $outdir
  skip_reslice=y

elif [ "$method" = "fugue" ]; then

  T -e "Unwarping distortions based on an acquired fieldmap"

  T $scriptdir/motion_correct.sh -k $diffusion -b $bval -r $bvec -o $outdir -M $mask -m eddy

  T $scriptdir/unwarp_fieldmap.sh -k $outdir/mc_$diffusion -f $dph -m $mag -M $mask -p $mag_mask -o $outdir -s

  T mv $outdir/unwarped_mc_$diffusion $outdir/mc_unwarped_$diffusion

else

  error_exit "ERROR: method \"$method\" is neither topup nor fugue"

fi

#-------------- fitting the tensor ------------------#

T $scriptdir/fit_tensor.sh -k $outdir/resliced_$diffusion -b $bval -r $outdir/bvec_ecc -m $outdir/unwarped_`basename $mask` -o $outdir

