#! /bin/sh

# makes a 2D gif from a 3D volume. 
# arguments after the first two are passed to slicer
in=$1
out=$2
shift 2

tmpdir=`mktemp -d`

slicer $in -s 3 $* -x 0.35 $tmpdir/sla.png -x 0.45 $tmpdir/slb.png -x 0.55 $tmpdir/slc.png -x 0.65 $tmpdir/sld.png \
                   -y 0.35 $tmpdir/sle.png -y 0.45 $tmpdir/slf.png -y 0.55 $tmpdir/slg.png -y 0.65 $tmpdir/slh.png \
                   -z 0.35 $tmpdir/sli.png -z 0.45 $tmpdir/slj.png -z 0.55 $tmpdir/slk.png -z 0.65 $tmpdir/sll.png

pngappend $tmpdir/sli.png + $tmpdir/slj.png + $tmpdir/slk.png + $tmpdir/sll.png - \
$tmpdir/sla.png + $tmpdir/slb.png + $tmpdir/slc.png + $tmpdir/sld.png - \
$tmpdir/sle.png + $tmpdir/slf.png + $tmpdir/slg.png + $tmpdir/slh.png $out

convert $out -fill grey -pointsize 60 -annotate +30+1130 $in $out

rm $tmpdir/sl?.png

rmdir $tmpdir