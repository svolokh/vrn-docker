#!/bin/bash

source /etc/profile
source /content/torch/install/bin/torch-activate

ls /content/data

export TERM=dumb
TMPDIR=/content/tmp
INPUT=$2

mkdir -p "$TMPDIR"

echo "Please wait. Your image is being processed.";

convert -auto-orient $INPUT $TMPDIR/"$(basename $INPUT)"

pushd face-alignment > /dev/null
th main.lua -model 2D-FAN-300W.t7 \
   -input $TMPDIR/$INPUT \
   -detectFaces true \
   -mode generate \
   -output $TMPDIR/"$(basename $INPUT)".txt \
   -device cpu \
   -outputFormat txt

exit=$?

if [ ! -f $TMPDIR/"$(basename $INPUT)".txt ]; then
    rm $TMPDIR/$INPUT
    echo "The face detector failed to find your face."
    cd ../
    exit 1
fi

if [ $exit -ne 0 ]; then
    echo "Error occured while running the face detector"
    cd ../
    exit 1
fi

popd > /dev/null
date
awk -F, 'BEGIN {
              minX=100000;
              maxX=0;
              minY=100000;
              maxY=0;
            }
            $1 > maxX { maxX=$1 }
            $1 < minX { minX=$1 }
            $2 > maxY { maxY=$2 }
            $2 < minY { minY=$2 }
            END {
              scale=90/sqrt((minX-maxX)*(minY-maxY));
              width=maxX-minX;
              height=maxY-minY;
              cenX=width/2;
              cenY=height/2;
              printf "%s %s %s\n",
                (minX-cenX)*scale,
                (minY-cenY)*scale,
                (scale)*100
   }' $TMPDIR/"$(basename $INPUT)".txt > $TMPDIR/"$(basename $INPUT)".crop

cat $TMPDIR/"$(basename $INPUT)".crop | \
    while read x y scale; do
    convert $TMPDIR/"$(basename $INPUT)" \
	-scale $scale% \
	-crop 192x192+$x+$y \
	-background white \
	-gravity center \
	-extent 192x192 \
	$TMPDIR/"$(basename $INPUT)"

    if [ $? -ne 0 ]; then
	echo "Error occured while cropping the image."
	exit 1
    fi

    echo "Cropped and scaled $fname"
done
date
rm $TMPDIR/"$(basename $INPUT)".crop

th process.lua \
   --model vrn-unguided.t7 \
   --input $TMPDIR/"$(basename $INPUT)"  \
   --output $TMPDIR/"$(basename $INPUT)".raw \
   --device cpu

if [ $? -ne 0 ]; then
    echo "Error occured while regressing the 3D volume."
    exit 1
fi

python raw2obj.py \
    --image $TMPDIR/"$(basename $INPUT)" \
    --volume $TMPDIR/"$(basename $INPUT)".raw \
    --obj /content/data/"$(basename $INPUT)".obj

if [ $? -ne 0 ]; then
    echo "Error occured while extracting the isosurface."
    rm $TMPDIR/$INPUT.txt
    rm $TMPDIR/$INPUT.raw
    exit 1
fi

rm $TMPDIR/"$(basename $INPUT)".txt
rm $TMPDIR/"$(basename $INPUT)".raw




