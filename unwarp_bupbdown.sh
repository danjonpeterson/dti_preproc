#! /bin/sh

#---------variables and defaults---------#
direction=y		            # default distortion direction
tmpdir=temp-unwarp_bupbdown         # name of directory for intermediate files
LF=$tmpdir/unwarp_bupbdown.log      # default log filename
outdir=.                            # put output in PWD
generate_report=y                   # generate a report 
reportdir=$tmpdir/report    # directory for html report
configfile=b02b0.cnf                # default config file. actually lives in ${FSLDIR}/etc/flirtsch/
scriptdir=`dirname $0`

usage_exit() {
      cat <<EOF

  Correction for B0 inhomogeneity using topup

  Usage:   
  
    $CMD -k <img> -a <acqpars file> -M <img> [option]
  
    -k <img>          : 4D DTI image
    -a <text>         : eddy/topup acquisition parameters file
    -M <img>          : mask file 
    -b <text>         : b-value file


    Option: 
    -s          : no not generate HTML report
    -o          : output directory (defaut: current working directory)
    -r          : report directory
    -c          : config file

example:
unwarp_bupbdown.sh -k diffusion_data.nii.gz -a acqpars.txt -M brain_mask.nii.gz 

EOF
    exit 1;
}

#---------------- Utility Functions --------------#

T () {

 E=0 
 if [ "$1" = "-e" ] ; then  # just outputting and logging a message with T -e 
  E=1; shift  
 fi
 
 cmd="$*"
 echo $* | tee -a $LF       # read the command into the console, and the log file

 if [ "$E" != "1" ] ; then 
  $cmd 2>&1 | tee -a $LF    # run the command. read the output into a the log file. Stderr is not directed to the logfile
 fi

 echo  | tee -a $LF         # write an empty line to the console and log file
}

test_varimg (){
    var=$1
    if [ "x$var" = "x" ]; then test=0; else  test=`imtest $1`; fi
    echo $test
}

test_varfile (){
    var=$1
    if [ "x$var" = "x" ]; then test=0 ; elif [ ! -f $var ]; then test=0; else test=1; fi
    echo $test
}

#------------- Parse Parameters  --------------------#
[ "$6" = "" ] && usage_exit

while getopts k:a:M:so:r:c:b: OPT
 do
 case "$OPT" in 
   "k" ) dti="$OPTARG";; 
   "a" ) acqparsfile="$OPTARG";; 
   "M" ) mask="$OPTARG";;  
   "s" ) generate_report=n;;
   "o" ) outdir="$OPTARG";;
   "r" ) reportdir="$OPTARG";;
   "c" ) configfile="$OPTARG";;
   "b" ) bval="$OPTARG";;
    * )  usage_exit;;
 esac
done;

if [ `test_varimg $dti` -eq 0 ]; then
 echo "ERROR: cannot find image for dti 4D data: $dti"
 exit 1;
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 echo "ERROR: cannot find image: $maskf"; 
 exit 1
fi; 

#--------- Distortion correction using blip up-blip down S0 images-------#

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir
touch $LF

## assume the first two images are the S0's [TODO: take args]
s0_count=`cat $bval | tr ' ' '\n' | grep -c ^0`
T fslroi $dti $tmpdir/S0_images 0 $s0_count

## do the thing
T topup --imain=$tmpdir/S0_images --datain=$acqparsfile --config=$configfile --out=$tmpdir/topup_out --fout=$tmpdir/field_est --iout=$tmpdir/unwarped_S0_images --verbose

## apply the warp to the brain mask
##T applytopup --imain=$mask --topup=$tmpdir/topup_out --datain=$acqparsfile --inindex=1 --out=$tmpdir/unwarped_brain_mask_raw --method=jac

##T fslmaths $tmpdir/unwarped_brain_mask_raw -thr 0.8 -bin $tmpdir/unwarped_brain_mask
T fslmaths $tmpdir/unwarped_S0_images -Tmean $tmpdir/avg_unwarped_S0
T bet $tmpdir/avg_unwarped_S0 $tmpdir/unwarped_brain -m -f 0.2



#--------------- copying results to output directory ------------#

mkdir -p $outdir

cp $tmpdir/topup_out* $outdir/
cp $tmpdir/unwarped_brain_mask.nii.gz $outdir/

## generate report
if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/unwarp_bupbdown_report.sh -t $tmpdir -r $reportdir -o $outdir
fi

cp $reportdir/*.html $outdir
