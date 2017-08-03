# *dti_preproc* - IBIC DTI preprocessing scripts

## Motivation
This project is a collection of scripts and utilities aimed at simplifing DTI preprocessing.

The main features of this package are: 

* Automatic generation of QA reports as standalone .html files
* Itegrated motion correction and EPI unwarping (both fieldmap-based unwarping and “blip-up, blip-down” unwarping)
* Support for processing pipelines based on GNU make
* Specify direction of unwarping. Supported directions are `y` (default) and `y-`, which is set by adding the `-Y` flag to `dti_preproc.sh` or the unwarp scripts.

These scripts are intended implement ‘state of the art’ preprocessing options by default. This includes motion correction with FSL’s ‘eddy’, with rotation of the b-vectors, and tensor estimation using RESTORE.


## Preparing the Data

   This script assumes all B0s and DWIs are concatenated into one 4d image, with the B0 images first. Depending on the type of EPI unwarping required, you may need to create an "acquisition parameter file" and/or an "index file" in FSL format, described [here](http://fsl.fmrib.ox.ac.uk/fsl/fslwiki/eddy/Faq#Why_do_I_need_more_than_two_rows_in_my_--acqp_file). You will also need to generate an initial brain mask.


## Make-Based Pipeline:

   These scripts can be integrated into a processing pipeline based on ‘GNU Make’, using the approach described in [Askren et al. 2016](http://journal.frontiersin.org/article/10.3389/fninf.2016.00002/full). **example_makefile.mk** can serve as a template, but will need to be modified for your particular environment.

   To help with functionality in make-based pipelines, there is the addtional flag `-T <name>` which allows you to supply a prefix to the temp directory to make sure two directiories don't end up with the same name while make is running concurrently.


## Files in the Repository

### main scripts

* **dti_preproc.sh** this is the main script it can call the other scripts in the appropriate order
* **unwarp_bupbdown.sh** unwarps EPI distortions using images acquired with the phase-encoding along opposite direction (i.e. “blip-up, blip-down” images)
* **motion_correct.sh** corrects for motion and eddy currents using fsl’s ‘eddy’
* **unwarp_fieldmap.sh** unwarps EPI distortions using an acquired fieldmap
* **fit_tensor.sh** fits the diffusion tensor (defaut: RESTORE as implemented in Camino)

### report generation
These are called by the main scripts but may be invoked on their own

* **unwarp\_bupbdown\_report.sh** [example](http://danjonpeterson.github.io/unwarp_bupbdown_report.html)  
* **motion\_correct\_report.sh** [example](http://danjonpeterson.github.io/motion_correct_report.html)
* **unwarp\_fieldmap\_report.sh** [example](http://danjonpeterson.github.io/unwarp_fieldmap_report.html)
* **fit\_tensor\_report.sh** [example](http://danjonpeterson.github.io/fit_tensor_report.html)


### utilites for preparing the data

* **concatenate_diffusion.sh** combines two runs of diffusion data, including 4d images, b-values and b-vectors.
* **rearrange_diffusion.sh** rearranges a diffusion run (again, including 4d images, bvals, bvecs)   


### utilities that are called by other scripts

* **eddy\_pars\_to\_xfm\_dir.py** takes a ‘motion parameter file’ as generated by eddy and makes a directory of linear transforms
* **image\_to\_movie.sh** takes a 4d image and creates an animated gif showing tri-planar images across various slices
* **image\_to\_gif.sh** takes 3D images and makes static images. also handles overlays (basically a wrapper for slicer)

### other resources

* **b02b0_fast.cnf** configuration file for topup that does a minimal amount of processing. Used for debugging/testing in “fast mode”
* **example_makefile.mk** an example makefile for gnu-make based processing


## Dependencies

* [**imagemagick**](http://www.imagemagick.org/script/index.php)
* [**whirlgif**](http://www.astro.auth.gr/~simos/cgi-bin/PDEs/Hyperbolic/whirlgif.c)
* [**fsl**](http://fsl.fmrib.ox.ac.uk/fsl/fslwiki/FslInstallation)
* [**camino**](http://web4.cs.ucl.ac.uk/research/medic/camino/pmwiki/pmwiki.php?n=Main.Guide)
* [**R**](https://www.r-project.org/) (with package *rmarkdown*)
* [**pandoc**](http://pandoc.org/installing.html)

----

## TO DO
* Correct min/max display info in header of output images
* Use [Gifsicle](https://www.lcdf.org/gifsicle/) (or something else) for gif making, since whirlgif appears to be defunct and non-free

###### Add to report
* versions of fsl, camino, etc
* embed entirety of log file somehow
* display rotating gif of bvecs
* display fieldmap estimated from *topup*
* display gif of residuals across DWIs