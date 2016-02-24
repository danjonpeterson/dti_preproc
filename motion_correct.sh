#! /bin/sh

# TODO: fix options, implement fast, get rid of flirt, MCflirt

usage_exit() {
      cat <<EOF

  DTI  correction for motion and eddy currents

  Version `echo "$VERSION" | awk '{print $1}'`

  Usage:
  
    $CMD -k <img> -b <bvals.txt> -r <bvecs.txt> [option]
      : corrects motion   
  
    -k <img>    : DTI 4D data
    -b <bvals.txt> : a text file containing a list of b-values
    -r <bvecs.txt> : a text file containing a list of b-vectors
    -M <img> : mask file for dti image 

  
    Option: 
    -o       : directory for output
    -i       : index file for eddy with topup
    -a       : acquisition parameter file for eddy with topup
    -t       : topup output basename 
    -n       : number of iterations for eddy
    -E       : don't run the commands, just echo them
    -F       : fast mode for testing (minimal iterations)
EOF


    exit 1;
}

#---------variables---------#
tmpdir=temp-motion_correct        # name of directory for intermediate files
log_filename=motion_correct.log   # default log filename
outdir=.                          # put output in PWD
generate_report=y                 # generate a report 
reportdir=$tmpdir/report          # directory for html report
eddy_iterations=4                 # number of iterations for EDDY
mode=normal                       # run mode (normal,fast,echo)
fast_testing=n                    # run with minimal processing for testing
method=eddy                       # use eddy without topup
scriptdir=`dirname $0`            # directory where dti_preproc scripts live
other_eddy_opts=""

#------------- parsing parameters ----------------#

[ "$4" = "" ] && usage_exit #show help message if fewer than four args

while getopts k:b:r:M:N:o:i:a:t:n:EF OPT
 do
 case "$OPT" in 
   "k" ) dti="$OPTARG";;
   "b" ) bval="$OPTARG";;
   "r" ) bvec="$OPTARG";;   
   "M" ) mask="$OPTARG";;
   "N" ) bvec_ecc=0;;
   "o" ) outdir="$OPTARG";;
   "i" ) indexfile="$OPTARG";;
   "a" ) acqparsfile="$OPTARG";;
   "t" ) topupbasename="$OPTARG"
         method="eddy_with_topup";;
   "n" ) eddy_iterations="$OPTARG";;
   "E" ) mode=echo;;
   "F" ) fast_testing=y;;
    * )  usage_exit;;
 esac
done;

#---------------- Utility Functions --------------#

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

mkdir -p $outdir

## clear, then make the temporary directory
if [ -e $tmpdir ]; then /bin/rm -Rf $tmpdir;fi
mkdir $tmpdir

LF=$tmpdir/$log_filename
touch $LF

#------------- verifying inputs ----------------#

if [ `test_varimg $dti` -eq 0 ]; then
 error_exit "ERROR: cannot find image for dti 4D data: $dph"
else
 dtidim4=`fslval $dti dim4`
fi

if [ "$bvec" = "" ] && [ "$bval" = "" ] ;  then
 test=1
else
 if [ `test_varfile $bvec` -eq 0 ]; then error_exit "ERROR: no bvecs file specified"; fi
 bvecl=`cat $bvec | awk 'END{print NR}'`; bvecw=`cat $bvec | wc -w`	
 if [ $bvecl != 3 ]; then error_exit "ERROR: bvecs file contains $bvecl lines, it should be 3 lines, each for x, y, z"; fi
 if [ "$bvecw" != "`expr 3 \* $dtidim4`" ]; then error_exit "ERROR: bvecs file contains $bvecw words, it should be 3 x $dtidim4 words"; fi
 if [ `test_varfile $bval` -eq 0 ]; then error_exit "ERROR: no bvals file specified"; fi
 bvall=`cat $bval | awk 'END{print NR}'`; bvalw=`cat $bval | wc -w`
 if [ $bvall != 1 ]; then error_exit "ERROR: bvals file contains $bvall lines, it should be 1 lines"; fi
 if [ $bvalw != $dtidim4 ]; then error_exit "ERROR: bvalc file contains $bvalw words, it should be $dtidim4 words"; fi 
fi

if  [ "$method" != "eddy" ] && [ "$method" != "eddy_with_topup" ]  ; then
 error_exit "ERROR unrecognized method: $method"
fi

if [ `test_varimg $mask` -eq 0 ]; then 
 error_exit "ERROR: cannot find mask image: $mask" 
fi

#------------- Motion correction ----------------#

if [ "$fast_testing" = "y" ]; then 
  eddy_iterations=0
  other_eddy_opts=--dont_peas
fi

if [ "$method" = "eddy" ]; then
 T -e using eddy
 ## make a dummy acqparams file
 echo 0 1 0 0.072 > $tmpdir/acqparams.txt  
 ## make index file (just n "1"'s)
 seq -s " " $dtidim4 | sed 's/[0-9]*/1/g' > $tmpdir/index.txt
 ## run eddy
 T eddy --imain=$dti --mask=$mask --index=${tmpdir}/index.txt --acqp=${tmpdir}/acqparams.txt --bvecs=$bvec --bvals=$bval --out=${tmpdir}/eddy_out --very_verbose --niter=$eddy_iterations $other_eddy_opts
 ## create xfm directory
 T $scriptdir/eddy_pars_to_xfm_dir.py ${tmpdir}/eddy_out.eddy_parameters ${tmpdir}/dti_ecc.mat
 ## rename output
 T mv $tmpdir/eddy_out.nii.gz $tmpdir/dti_ecc.nii.gz 
fi


if [ "$method" = "eddy_with_topup" ]; then
 T -e using eddy with topup output
 ## run eddy
 T eddy --imain=$dti --mask=$mask --index=$indexfile --acqp=$acqparsfile --bvecs=$bvec --bvals=$bval --out=${tmpdir}/eddy_out --topup=$topupbasename --very_verbose --niter=$eddy_iterations $other_eddy_opts
 ## create xfm directory
 T $scriptdir/eddy_pars_to_xfm_dir.py ${tmpdir}/eddy_out.eddy_parameters ${tmpdir}/dti_ecc.mat 
 ## rename output
 T mv $tmpdir/eddy_out.nii.gz $tmpdir/dti_ecc.nii.gz 
 T fslmaths $tmpdir/dti_ecc.nii.gz $outdir/mc_unwarped_${dti}
fi

#------------- rotating the bvecs  ----------------#
#TODO: move to a separate script

## clear and make output motion parameter files
for i in translation.par rotation.par scale.par skew.par ; do 
 if [ -e ${tmpdir}/${i} ] ; then rm -Rf ${tmpdir}/${i}; fi
 touch $tmpdir/${i};
done  

cp $bvec $tmpdir/bvec_ecc

i=0
while [ $i -lt $dtidim4 ]; do ## loop through DWIs
 j=`zeropad $i 4`
 ## use fsl utility 'avscale; to extract translation, rotation scale and skew parameters for this DWI
 v=`avscale --allparams $tmpdir/dti_ecc.mat/MAT_$j | head -13 | tail -7 | cut -d "=" -f 2 | grep [0-9]` 
 echo $v | awk '{print $4,$5,$6}' >> $tmpdir/translation.par
 echo $v | awk '{printf "%f %f %f\n",$1*180/3.141592653,$2*180/3.141592653,$3*180/3.141592653}' >> $tmpdir/rotation.par
 echo $v | awk '{print $7,$8,$9}' >> $tmpdir/scale.par
 echo $v | awk '{print $10,$11,$12}' >> $tmpdir/skew.par


 i=`expr $i + 1`
done ## end while loop across DWIs

#TODO merge these loops

numbvecs=`cat ${bvec} | head -1 | tail -1 | wc -w`

ii=1
rm -f $tmpdir/bvec_ecc
touch $tmpdir/bvec_ecc

while [ $ii -le ${numbvecs} ] ; do # loop through dwis
    
 izeroindexed=`expr $ii - 1`

 matrix=$tmpdir/dti_ecc.mat/MAT_`zeropad $izeroindexed 4`

 # extract rotation component of MC xform
 m11=`avscale ${matrix} | grep Rotation -A 1 | tail -n 1| awk '{print $1}'`
 m12=`avscale ${matrix} | grep Rotation -A 1 | tail -n 1| awk '{print $2}'`
 m13=`avscale ${matrix} | grep Rotation -A 1 | tail -n 1| awk '{print $3}'`
 m21=`avscale ${matrix} | grep Rotation -A 2 | tail -n 1| awk '{print $1}'`
 m22=`avscale ${matrix} | grep Rotation -A 2 | tail -n 1| awk '{print $2}'`
 m23=`avscale ${matrix} | grep Rotation -A 2 | tail -n 1| awk '{print $3}'`
 m31=`avscale ${matrix} | grep Rotation -A 3 | tail -n 1| awk '{print $1}'`
 m32=`avscale ${matrix} | grep Rotation -A 3 | tail -n 1| awk '{print $2}'`
 m33=`avscale ${matrix} | grep Rotation -A 3 | tail -n 1| awk '{print $3}'`
 
 # read the iith b-vector
 X=`cat ${bvec} | awk -v x=${ii} '{print $x}' | head -n 1 | tail -n 1 | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}'`
 Y=`cat ${bvec} | awk -v x=${ii} '{print $x}' | head -n 2 | tail -n 1 | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}'`
 Z=`cat ${bvec} | awk -v x=${ii} '{print $x}' | head -n 3 | tail -n 1 | awk -F"E" 'BEGIN{OFMT="%10.10f"} {print $1 * (10 ^ $2)}'`

 # do the matrix multiplication
 rX=`echo "scale=7;  (${m11} * $X) + (${m12} * $Y) + (${m13} * $Z)" | bc -l`
 rY=`echo "scale=7;  (${m21} * $X) + (${m22} * $Y) + (${m23} * $Z)" | bc -l`
 rZ=`echo "scale=7;  (${m31} * $X) + (${m32} * $Y) + (${m33} * $Z)" | bc -l`

 # uncomment next line if you want to check the rotation math
 # echo $X $Y $Z to $rX $rY $rZ via $matrix

 # using 'paste' for horizontal concatenation of the corrected vectors
 (echo $rX;echo $rY;echo $rZ) | paste $tmpdir/bvec_ecc - > $tmpdir/rotate_bvecs_tempfile.txt
 mv $tmpdir/rotate_bvecs_tempfile.txt $tmpdir/bvec_ecc
    
 ii=`expr $ii + 1`
done

# reformat with leading zero and spaces
cat $tmpdir/bvec_ecc | awk '{for(i=1;i<=NF;i++)printf("%10.6f ",$i);printf("\n")}' > $tmpdir/rotate_bvecs_tempfile.txt
mv $tmpdir/rotate_bvecs_tempfile.txt $tmpdir/bvec_ecc


#--------------- copying results to output directory ------------#

if [ "$bvec_ecc" != 0 ]; then
 T cp $tmpdir/bvec_ecc $outdir/bvec_mc.txt
fi

if [ "$method" = "eddy_with_topup" ]; then
 T fslmaths $tmpdir/dti_ecc.nii.gz $outdir/mc_unwarped_`basename $dti`
else
 T fslmaths $tmpdir/dti_ecc.nii.gz $outdir/mc_`basename $dti`
fi


T mkdir $outdir/dti_ecc.mat

T cp $tmpdir/dti_ecc.mat/* $outdir/dti_ecc.mat/

if [ "$method" = "eddy_with_topup" ]; then
 supplemental_report_params="-i $indexfile"
fi


#--------------- generate report ------------#

if [ "$generate_report" != "n" ] ; then 
 T $scriptdir/motion_correct_report.sh -t $tmpdir -r $reportdir -o $outdir -k $dti -m $method $supplemental_report_params
fi

cp $reportdir/*.html $outdir/
