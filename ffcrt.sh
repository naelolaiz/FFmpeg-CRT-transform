#!/bin/bash -x

# FFmpeg CRT transform script / VileR 2021
# parameter 1 = config file
# parameter 2 = input video/image
# parameter 3 = output video/image

EnableDelayedExpansion=
LOGLVL=error

#+++++++++++++++++++++++++#
# Check cmdline arguments #
#+++++++++++++++++++++++++#
script_file=$(basename "$0")
config_file="$1"
input_file="$2"
output_file="$3"

if [ -z "$config_file" ] || [ -z "$input_file" ]
then
  echo ""
  echo FFmpeg CRT transform script / VileR 2021
  echo Conversion to shell script / Madis Kaal 2022
  echo ""
  echo "USAGE:  $script_file <config_file> <input_file> [output_file]"
  echo ""
  echo "   input_file must be a valid image or video.  If output_file is omitted, the"
  echo '   output will be named "(input_file)_(config_file).(input_ext)"'
  exit 1
fi

if [ -z "$output_file" ]
then
  p=$(dirname $2)
  b=$(basename $2 | awk -F"." '{print $1}')
  c=$(basename $1 | awk -F"." '{print $1}')
  x=$(basename $2 | awk -F"." '{print $2}')
  output_file="$p"/"$b"_"$c"."$x"
else
  x=$(basename "$output_file" | awk -F"."  '{print $2}')
fi
OUTEXT=$x
OUTFILE=$output_file

if [ ! -f "$input_file" ]
then
  echo $input_file not found
  exit 1
fi

if [ ! -f "$config_file" ]
then
  echo $config_file not found
  exit 1
fi


#++++++++++++++++++++++++++++++++++++++++++++++#
# Find input dimensions and type (image/video) #
#++++++++++++++++++++++++++++++++++++++++++++++#

IX=
IY=
FC= 
for i in $(ffprobe -hide_banner -loglevel quiet -select_streams v:0 -show_entries stream=width,height,nb_frames $input_file | grep "=")
do
  n=$(echo $i | awk -F"=" '{print $1}')
  v=$(echo $i | awk -F"=" '{print $2}')
  if [ "$n" == "width" ]
  then
    IX=$v
  fi
  if [ "$n" == "height" ]
  then
    IY=$v
  fi
  if [ "$n" == "nb_frames" ]
  then
    FC=$v
  fi
done

if [ -z "$IX" ] || [ -z "$IY" ] || [ -z "$FC" ]
then
  echo ""
  echo "Could not get media info for input file \"$input_file\" (invalid image/video?)"
  exit 1
fi

if $(echo $input_file | grep -q ".mkv")
then
  FC=unknown
fi

if [ "$FC" != "N/A" ]
then
  IS_VIDEO=1
else
  IS_VIDEO=
fi

#++++++++++#
# Settings #
#++++++++++#

# Read config file / check for required external files:

while read i
do
  l=$(echo $i | awk -F";" '{print $1}')
  if [ ! -z "$l" ]
  then
    k=$(echo $l | awk '{print $1}')
    v=$(echo $l | awk '{print $2}')
    if [ "$k" == "16BPC_PROCESSING" ]
    then
      k="PROCESSING_16BPC"
    fi
    export $k=$v
  fi
done < $config_file

if [ ! -f "_$OVL_TYPE.png" ]
then
  echo File not found: _$OVL_TYPE.png
  exit 1
fi

# Set temporary + final output parameters:

if [ "$IS_VIDEO" == "1" ]
then
	if [ "$OFORMAT" == "0" ]
	then
		FIN_OUTPARAMS="-pix_fmt rgb24 -c:a copy -c:v libx264rgb -crf 8"
		FIN_MATRIXSTR=" "
	fi
	if [ "$OFORMAT" == "1" ]
	then
		FIN_OUTPARAMS="-pix_fmt yuv444p10le -color_primaries 1 -color_trc 1 -colorspace 1 -color_range 2 -c:v libx264 -crf 8 -c:a copy"
		FIN_MATRIXSTR=", scale=iw:ih:flags=neighbor+full_chroma_inp:in_range=full:out_range=full:out_color_matrix=bt709"
	fi
	if [ "$PROCESSING_16BPC" == "yes" ]
	then
		TMP_EXT="mkv"
		TMP_OUTPARAMS="-pix_fmt gbrp16le -c:a copy -c:v ffv1"
	else
		TMP_EXT="avi"
		TMP_OUTPARAMS="-c:a copy -c:v libx264rgb -crf 0"
	fi
else
	if [ "$OFORMAT" == "0" ]
	then
	  FIN_MATRIXSTR=" "
	  FIN_OUTPARAMS="-frames:v 1 -pix_fmt rgb24"
	fi
	if [ "$OFORMAT" == "1" ]
	then
	  FIN_MATRIXSTR=" "
	  FIN_OUTPARAMS="-frames:v 1 -pix_fmt rgb48be"
	fi
	if [ "$PROCESSING_16BPC" == "yes" ]
	then
          TMP_EXT="mkv"
	  TMP_OUTPARAMS="-pix_fmt gbrp16le -c:v ffv1"
	else
	  TMP_EXT="png"
	  TMP_OUTPARAMS=" "
	fi
fi

# Bit depth-dependent vars:

if [ "$PROCESSING_16BPC " == "yes" ]
then
	RNG=65536
	RGBFMT=gbrp16le
	KLUDGEFMT=gbrpf32le
else
	RNG=256
	RGBFMT=rgb24
	KLUDGEFMT=rgb24
fi

# Set some shorthand vars and calculate stuff:

SXINT=$(echo "" | awk "{print int($IX * $PRESCALE_BY)}")
PX=$(echo "" | awk "{print int($IX * $PRESCALE_BY * $PX_ASPECT)}")
PY=$(echo "" | awk "{print int($IY * $PRESCALE_BY)}")
OX=$(echo "" | awk "{print int($OY * $OASPECT + 0.5)}")
SWSFLAGS="accurate_rnd+full_chroma_int+full_chroma_inp"

if [ "$V_PX_BLUR"=="0" ]
then
  VSIGMA=0.1
else
  VSIGMA=$(echo "" | awk "{print $V_PX_BLUR / 100 * $PRESCALE_BY}")
fi

if [ "$VIGNETTE_ON" == "yes" ]
then
	if [ "$PROCESSING_16BPC" == "yes" ]
	then 
	  VIGNETTE_STR="[ref]; color=c=#FFFFFF:s=${PX}x${PY},format=rgb24[mkscale];\
		[mkscale][ref]scale2ref=flags=neighbor[mkvig][novig];\
		[mkvig]setsar=sar=1/1, vignette=PI*$VIGNETTE_POWER,format=gbrp16le[vig];\
		[novig][vig]blend=all_mode='multiply':shortest=1,"
	else
	  VIGNETTE_STR=", vignette=PI*$VIGNETTE_POWER," 
	fi
else
	VIGNETTE_STR=","
fi

if [ "$FLAT_PANEL" == "yes" ]
then
	SCANLINES_ON="no"
	CRT_CURVATURE="0"
	OVL_ALPHA="0"
fi

# Curvature factors


c=$(echo "$BEZEL_CURVATURE < $CRT_CURVATURE" | bc -l)
if [ "$c"  == "1" ]
then
  BEZEL_CURVATURE=$CRT_CURVATURE
fi

c=$(echo "$CRT_CURVATURE != 0.0" | bc -l)
if [ "$c" == "1" ]
then
  LENSC=", pad=iw+8:ih+8:4:4:black, lenscorrection=k1=$CRT_CURVATURE:k2=$CRT_CURVATURE, crop=iw-8:ih-8"
fi

c=$(echo "$BEZEL_CURVATURE != 0.0" | bc -l)
if [ "$c" == "1" ]
then
  BZLENSC=", scale=iw*2:ih*2:flags=gauss, pad=iw+8:ih+8:4:4:black, lenscorrection=k1=$BEZEL_CURVATURE:k2=$BEZEL_CURVATURE, crop=iw-8:ih-8, scale=iw/2:ih/2:flags=gauss"
fi

# Scan factor

if [ "$SCAN_FACTOR" == "half" ]
then
	SCAN_FACTOR=0.5
	SL_COUNT=$(( $IY / 2 ))
else
	if [ "$SCAN_FACTOR" == "double" ]
	then
		SCAN_FACTOR=2
		SL_COUNT=$(( $IY * 2 ))
	else
		SCAN_FACTOR=1
		SL_COUNT=$IY
	fi
fi

# Handle monochrome settings; special cases: 'p7' (decay/latency are processed differently and require a couple more curve maps),
# 'paperwhite' (uses a texture overlay), 'lcd*' (optional texture overlay + if FLAT_PANEL then pixel grid is inverted too)

grain=$(echo "$LCD_GRAIN > 0.0" | bc -l)

if [ "$MONITOR_COLOR" == "white" ]
then
  MONOCURVES=""
fi

if [ "$MONITOR_COLOR" == "paperwhite" ]
then
  MONOCURVES=""
  TEXTURE_OVL="paper"
fi

if [ "$MONITOR_COLOR" == "green1" ]
then
  MONOCURVES="curves=r='0/0 .77/0 1/.45':g='0/0 .77/1 1/1':b='0/0 .77/.17 1/.73',"
fi

if [ "$MONITOR_COLOR" == "green2" ]
then
  MONOCURVES="curves=r='0/0 .43/.16 .72/.30 1/.56':g='0/0 .51/.53 .82/1 1/1':b='0/0 .43/.16 .72/.30 1/.56',"
fi

if [ "$MONITOR_COLOR" == "bw-tv" ]
then
  MONOCURVES="curves=r='0/0 .5/.49 1/1':g='0/0 .5/.49 1/1':b='0/0 .5/.62 1/1',"
fi

if [ "%MONITOR_COLOR%" == "amber" ]
then
  MONOCURVES="curves=r='0/0 .25/.45 .8/1 1/1':g='0/0 .25/.14 .8/.55 1/.8':b='0/0 .8/0 1/.29',"
fi

if [ "$MONITOR_COLOR" == "plasma" ]
then
  MONOCURVES="curves=r='0/0 .13/.27 .52/.83 .8/1 1/1':g='0/0 .13/0 .52/.14 .8/.35 1/.54':b='0/0 1/0',"
fi

if [ "$MONITOR_COLOR" == "eld" ]
then
  MONOCURVES="curves=r='0/0 .46/.49 1/1':g='0/0 .46/.37 1/.94':b='0/0 .46/0 1/.29',"
fi

# allow lcd grain only for the appropriate monitor types 

if [ "$MONITOR_COLOR" == "lcd" ]
then
  MONOCURVES="curves=r='0/.09 1/.48':g='0/.11 1/.56':b='0/.20 1/.35',"
  PXGRID_INVERT=1
  if [ "$grain" == "1" ]
  then
    TEXTURE_OVL=lcdgrain
  fi 
fi

if [ "$MONITOR_COLOR" == "lcd-lite" ]
then
  MONOCURVES="curves=r='0/.06 1/.64':g='0/.15 1/.77':b='0/.35 1/.65',"
  PXGRID_INVERT=1
  if [ "$grain" == "1" ]
  then
    TEXTURE_OVL=lcdgrain
  fi 
fi

if [ "$MONITOR_COLOR" == "lcd-lwhite" ]
then
  MONOCURVES="curves=r='0/.09 1/.82':g='0/.18 1/.89':b='0/.29 1/.93',"
  PXGRID_INVERT=1
  if [ "$grain" == "1" ]
  then
    TEXTURE_OVL=lcdgrain
  fi 
fi

if [ "$MONITOR_COLOR" == "lcd-lblue" ]
then
  MONOCURVES="curves=r='0/.00 1/.62':g='0/.22 1/.75':b='0/.73 1/.68',"
  PXGRID_INVERT=1
  if [ "$grain" == "1" ]
  then
    TEXTURE_OVL=lcdgrain
  fi 
fi

MONO_STR1=" "
MONO_STR2=" "

if [ "$MONITOR_COLOR" != "rgb" ]
then
	OVL_ALPHA="0"
	MONO_STR1="format=gray16le,format=gbrp16le,"
	MONO_STR2=$MONOCURVES
fi

if [ "$MONITOR_COLOR" == "p7" ]
then
	MONOCURVES_LAT="curves=r='0/0 .6/.31 1/.75':g='0/0 .25/.16 .75/.83 1/.94':b='0/0 .5/.76 1/.97'"
	MONOCURVES_DEC="curves=r='0/0 .5/.36 1/.86':g='0/0 .5/.52 1/.89':b='0/0 .5/.08 1/.13'"
	DECAYDELAY=$(echo "$LATENCY / 2" | bc -l)
	if [ "$IS_VIDEO" == "1" ]
	then
		MONO_STR2="split=4 [orig][a][b][c];\
		[a] tmix=$LATENCY, $MONOCURVES_LAT [lat];\
		[b] lagfun=$P_DECAY_FACTOR [dec1]; [c] lagfun=$P_DECAY_FACTOR*0.95 [dec2];\
		[dec2][dec1] blend=all_mode='lighten':all_opacity=0.3, $MONOCURVES_DEC, setpts=PTS+($DECAYDELAY/FR)/TB [decay];\
		[lat][decay] blend=all_mode='lighten':all_opacity=$P_DECAY_ALPHA [p7];\
		[orig][p7] blend=all_mode='screen',format=$RGBFMT,"
	else
		MONO_STR2="split=3 [orig][a][b];\
		[a] $MONOCURVES_LAT [lat];\
		[b] $MONOCURVES_DEC [decay];\
		[lat][decay] blend=all_mode='lighten':all_opacity=$P_DECAY_ALPHA [p7];\
		[orig][p7] blend=all_mode='screen',format=$RGBFMT,"
	fi
fi

# Can skip some stuff where not needed

c=$(echo "$OVL_ALPHA == 0.0" | bc -l)
if [ "$c" == "1" ]
then
  SKIP_OVL=1
else
  SKIP_OVL=0
fi

c=$(echo "$BRIGHTEN == 1.0" | bc -l)
if [ "$c" == "1" ]
then
  SKIP_BRI=1
else
  SKIP_BRI=0
fi


FFSTART=$(date)

if [ "$FC" != "N/A" ]
then
	echo ""
	echo Input frame count: $FC
	echo ---------------------------
fi

#+++++++++++++++++++++++++++++++++++++++++++++++++#
# Create bezel with rounded corners and curvature #
#+++++++++++++++++++++++++++++++++++++++++++++++++#

echo Bezel:

if [ "$CORNER_RADIUS%" == "0" ]
then
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y \
	-f lavfi -i "color=c=#ffffff:s=${PX}x${PY}, format=rgb24 $BZLENSC" \
	-frames:v 1 TMPbezel.png
else
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y \
	-f lavfi -i "color=s=1024x1024, format=gray, geq='lum=if(lte((X-W)^2+(Y-H)^2, 1024*1024), 255, 0)', scale=${CORNER_RADIUS}:${CORNER_RADIUS}:flags=lanczos" \
	-filter_complex "color=c=#ffffff:s=${PX}x${PY}, format=rgb24[bg];\
		[0] split=4 [tl][c2][c3][c4];\
		[c2] transpose=1 [tr];\
		[c3] transpose=3 [br];\
		[c4] transpose=2 [bl];\
		[bg][tl] overlay=0:0:format=rgb [p1];\
		[p1][tr] overlay=${PX}-${CORNER_RADIUS}:0:format=rgb [p2];\
		[p2][br] overlay=${PX}-${CORNER_RADIUS}:${PY}-${CORNER_RADIUS}:format=rgb [p3];\
		[p3][bl] overlay=x=0:y=${PY}-${CORNER_RADIUS}:format=rgb $BZLENSC" \
	-frames:v 1 TMPbezel.png
fi

if [ "$?" != "0" ]
then
  exit 1
fi

#+++++++++++++++++++++++++++++++++#
# Create scanlines, add curvature #
#+++++++++++++++++++++++++++++++++#

if [ "$SCANLINES_ON" == "yes" ]
then
	echo ""
	echo "Scanlines:"
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -f lavfi \
	-i nullsrc=s=1x100 \
	-vf "format=gray,\
geq=lum='if(lt(Y,${PRESCALE_BY}/${SCAN_FACTOR}), pow(sin(Y*PI/(${PRESCALE_BY}/${SCAN_FACTOR})), 1/${SL_WEIGHT})*255, 0)',\
crop=1:${PRESCALE_BY}/${SCAN_FACTOR}:0:0,\
scale=${PX}:ih:flags=neighbor"\
	-frames:v 1 TMPscanline.png

	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -loop 1 -framerate 1 -t $SL_COUNT \
	-i TMPscanline.png\
	-vf "format=gray16le,\
tile=layout=1x${SL_COUNT},\
scale=iw*3:ih*3:flags=gauss ${LENSC}, scale=iw/3:ih/3:flags=gauss,\
format=gray16le, format=${RGBFMT}"\
	-frames:v 1 $TMP_OUTPARAMS TMPscanlines.$TMP_EXT
	
	if [ "$?" != "0" ]
	then
	  exit 1
	fi
	
fi

#**************************************************#
# Create shadowmask/texture overlay, add curvature #
#**************************************************#

echo ""
echo Shadowmask overlay:

c=$(echo "$OVL_ALPHA > 0.0" | bc -l)
if [ $c == "0" ]
then
	# (if shadowmask alpha is 0, just make a blank canvas)
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -f lavfi -i "color=c=#00000000:s=${PX}x${PY},format=rgba" \
	-frames:v 1 TMPshadowmask.png
else
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i _$OVL_TYPE.png -vf \
		"lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)',\
scale=round(iw*${OVL_SCALE}):round(ih*${OVL_SCALE}):flags=lanczos+${SWSFLAGS}" \
	TMPshadowmask1x.png
	
	OVL_X=
	OVL_Y=
	
    for i in $(ffprobe -hide_banner -loglevel quiet -select_streams v:0 -show_entries stream=width,height TMPshadowmask1x.png | grep "=")
	do
	  n=$(echo $i | awk -F"=" '{print $1}')
	  v=$(echo $i | awk -F"=" '{print $2}')
	  if [ "$n" == "width" ]
	  then
	    OVL_X=$v
	  fi
	  if [ "$n" == "height" ]
	  then
	    OVL_Y=$v
	  fi
	done

	TILES_X=$(( $PX / $OVL_X + 1 ))
	TILES_Y=$(( $PY / $OVL_Y + 1 ))
	
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -loop 1 -i TMPshadowmask1x.png -vf \
		"tile=layout=${TILES_X}x${TILES_Y},\
crop=${PX}:${PY},\
scale=iw*2:ih*2:flags=gauss ${LENSC},\
scale=iw/2:ih/2:flags=bicubic,\
lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)'" \
	-frames:v 1 TMPshadowmask.png
	
	if [ "$?" != "0" ]
	then
	  exit 1
	fi
	
fi

if [ "$TEXTURE_OVL" = "lcdgrain" ]
then
	# Otherwise "%TEXTURE_OVL%"=="lcdgrain" here
	# LCD grain overlay (for lcd* monitor types only), doesn't need curvature

	GRAINX=$(echo "$OY * $OASPECT * 50.0 / 100.0" | bc -l)
	GRAINY=$(echo "$OY * 50.0 / 100.0" | bc -l)

	echo ""
	echo Texture overlay:
	
	ffmpeg -hide_banner -y -loglevel $LOGLVL -stats -filter_complex "color=#808080:s=${GRAINX}x%${GRAINY}, \
noise=all_seed=5150:all_strength=${LCD_GRAIN}, format=gray, \
scale=${OX}:${OY}:flags=lanczos, format=rgb24 " -frames:v 1 TMPtexture.png
fi

if [ "$TEXTURE_OVL" == "paper" ]
then
	# Phosphor overlay for monochrome "paper white" only, doesn't need curvature
	PAPERX=$(echo "$OY * $OASPECT * 67 / 100" | bc -l)
	PAPERY=$(echo "$OY * 67 / 100" | bc -l)

	echo ""
	echo Texture overlay:
	
	ffmpeg -hide_banner -y -loglevel $LOGLVL -stats -f lavfi -i "color=c=#808080:s=${PAPERX}x${PAPERY}" \
	  -filter_complex "noise=all_seed=5150:all_strength=100:all_flags=u, format=gray, \
lutrgb='r=(val-70)*255/115:g=(val-70)*255/115:b=(val-70)*255/115', \
format=rgb24, lutrgb='r=if(between(val,0,101),207,if(between(val,102,203),253,251)):\
g=if(between(val,0,101),238,if(between(val,102,203),225,204)):\
b=if(between(val,0,101),255,if(between(val,102,203),157,255))',\
format=gbrp16le,\
lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)',\
scale=${OX}:${OY}:flags=bilinear,\
gblur=sigma=3:steps=6,\
lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)',\
format=gbrp16le,format=rgb24"  -frames:v 1 TMPtexture.png

fi


#+++++++++++++++++++++++++++++++++++#
# Create discrete pixel grid if set #
#+++++++++++++++++++++++++++++++++++#

if [ "$FLAT_PANEL" == "yes" ]
then

  LUM_GAP=$(echo "255-255 * $PXGRID_ALPHA" | bc -l)
  LUM_PX=255
  if [ "$PXGRID_INVERT" == "1" ]
  then
    LUM_GAP=$(echo "255 * $PXGRID_ALPHA" | bc -l)
    LUM_PX=0
  fi
  GX=$(echo "$PRESCALE_BY / $PX_FACTOR_X" | bc -l)
  GY=$(echo "$PRESCALE_BY / $PX_FACTOR_Y" | bc -l)

  echo ""
  echo Grid:
  
  ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -f lavfi \
    -i nullsrc=s=${SXINT}x${PY} -vf "format=gray,\
geq=lum='if(gte(mod(X,${GX}),${GX}-${PX_X_GAP})+gte(mod(Y,${GY}),${GY}-${PX_Y_GAP}),${LUM_GAP},${LUM_PX})',\
format=gbrp16le,\
lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)',\
scale=${PX}:ih:flags=bicubic,\
lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)',\
format=gbrp16le,format=rgb24" -frames:v 1 TMPgrid.png	

    if [ "$?" != "0" ]
    then
      exit 1
    fi
fi

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Pre-process if needed: phosphor decay (video only), invert, pixel latency (video only) #
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

SCALESRC=$input_file
PREPROCESS=
VF_INVERT=
VF_DECAY=

if [ "$INVERT_INPUT" == "yes" ]
then
  PREPROCESS=1
  VF_PRE=negate
fi

if [ "$IS_VIDEO" == "1" ]
then
  c=$(echo "$LATENCY > 0.0" | bc -l)
  if [ "$c" == "1" ]
  then 
    if [ "$MONITOR_COLOR" != "p7" ]
    then
	PREPROCESS=1
	if [ ! -z "$VF_PRE" ]
	then
	  VF_PRE=", $VF_PRE"
	fi
	
	VF_PRE="split [o][2lat]; \
[2lat] tmix=${LATENCY}, setpts=PTS+((${LATENCY}/2)/FR)/TB [lat]; \
[lat][o] blend=all_opacity=${LATENCY_ALPHA} ${VF_PRE}"
    fi
  fi
fi

if [ ! -z "$IS_VIDEO" ]
then
  c=$(echo "$P_DECAY_FACTOR > 0.0" | bc -l)
  if [ "$c" == "1" ]
  then
    if [ "$MONITOR_COLOR" != "p7" ]
    then
	PREPROCESS=1
	if [ ! -z "$VF_PRE" ]
	then
	  VF_PRE=", ${VF_PRE}"
	fi
	VF_PRE=" [0] split [orig][2lag]; \
[2lag] lagfun=${P_DECAY_FACTOR} [lag]; \
[orig][lag] blend=all_mode='lighten':all_opacity=${P_DECAY_ALPHA} ${VF_PRE}"
    fi
  fi
fi

if [ ! -z "$PREPROCESS" ]
then
	echo ""
	echo "Step00 (preprocess):"
	
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i $input_file -filter_complex "${VF_PRE}"\
	  ${TMP_OUTPARAMS} TMPstep00.${TMP_EXT}
	  
        if [ "$?" != "0" ]
        then
          exit 1
        fi
	
	SCALESRC=TMPstep00.${TMP_EXT}
fi

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Scale nearest neighbor, go 16bit/channel, apply grid, gamma & pixel blur #
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

# If we have a grid, the inputs + first part of filter are different

if [ -z "$PXGRID_INVERT" ]
then
  GRIDBLENDMODE='multiply'
else
  GRIDBLENDMODE='screen'
fi

GRIDFILTERFRAG=

if [ "$FLAT_PANEL" == "yes" ]
then
  GRIDFILTERFRAG="[scaled];movie=TMPgrid.png[grid];[scaled][grid]blend=all_mode=${GRIDBLENDMODE}"
fi

echo ""
echo "Step01:"

ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i $SCALESRC -filter_complex \
	"scale=iw*${PRESCALE_BY}:ih:flags=neighbor,\
format=gbrp16le,\
lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)',\
scale=iw*${PX_ASPECT}:ih:flags=fast_bilinear,\
scale=iw:ih*${PRESCALE_BY}:flags=neighbor\
${GRIDFILTERFRAG},\
gblur=sigma=${H_PX_BLUR}/100*${PRESCALE_BY}*${PX_ASPECT}:sigmaV=${VSIGMA}:steps=3" \
-c:v ffv1 -c:a copy TMPstep01.mkv

if [ "$?" != "0" ]
then
  exit 1
fi

#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Add halation, revert gamma, normalize blackpoint, revert bit depth, add curvature #
#+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

# (Real halation should come after scanlines & before shadowmask, but that turned out ugly)

echo ""
echo "Step02:"

if [ "$HALATION_ON" == "yes" ]
then
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i TMPstep01.mkv -filter_complex \
		"[0]split[a][b],\
[a]gblur=sigma=${HALATION_RADIUS}:steps=6[h],\
[b][h]blend=all_mode='lighten':all_opacity=${HALATION_ALPHA},\
lutrgb='r=clip(gammaval(0.454545)*(258/256)-2*256 ,minval,maxval):\
g=clip(gammaval(0.454545)*(258/256)-2*256 ,minval,maxval):\
b=clip(gammaval(0.454545)*(258/256)-2*256 ,minval,maxval)',\
lutrgb='r=val+(${BLACKPOINT}*256*(maxval-val)/maxval):\
g=val+(${BLACKPOINT}*256*(maxval-val)/maxval):\
b=val+(${BLACKPOINT}*256*(maxval-val)/maxval)',\
format=${RGBFMT} ${LENSC}" \
	$TMP_OUTPARAMS TMPstep02.${TMP_EXT}
else
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i TMPstep01.mkv -vf \
		"lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)',\
lutrgb='r=val+(${BLACKPOINT}*256*(maxval-val)/maxval):g=val+(${BLACKPOINT}*256*(maxval-val)/maxval):\
b=val+(${BLACKPOINT}*256*(maxval-val)/maxval)',format=${RGBFMT} ${LENSC}" \
	${TMP_OUTPARAMS} TMPstep02.${TMP_EXT}
fi

if [ "$?" != "0" ]
then
  exit 1
fi

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Add bloom, scanlines, shadowmask, rounded corners + brightness fix #
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

# Can be skipped if none of the above are needed:
if [ "$SCANLINES_ON" == "no" ]
then
  if [ "$BEZEL_CURVATURE" == "$CRT_CURVATURE" ]
  then
    c=$(echo "$CORNER_RADIUS == 0.0" | bc -l)
    if [ "$c" == "1" ]
    then
      if [ ! -z "$SKIP_OVL" ] && [ ! -z "$SKIP_BRI" ]
        then
	  rm -f TMPstep03.$TMP_EXT
	  mv TMPstep02.$TMP_EXT TMPstep03.$TMP_EXT
	fi
    fi
  fi
fi

if [ "$SCANLINES_ON" == "yes" ]
then

	SL_INPUT=TMPscanlines.${TMP_EXT}
	if [ "$BLOOM_ON" == "yes" ]
	then
		SL_INPUT=TMPbloom.$TMP_EXT
		echo ""
		echo "Step02-bloom:"
		
		ffmpeg -hide_banner -loglevel $LOGLVL -stats -y\
		-i TMPscanlines.${TMP_EXT} -i TMPstep02.${TMP_EXT} -filter_complex \
			"[1]lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)', \
hue=s=0, lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)'[g],\
[g][0]blend=all_expr='if(gte(A,${RNG}/2), (B+(${RNG}-1-B)*${BLOOM_POWER}*(A-${RNG}/2)/(${RNG}/2)), B)',\
setsar=sar=1/1" $TMP_OUTPARAMS $SL_INPUT
	fi
	
	echo ""
	echo "Step03:"
	
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y\
	-i TMPstep02.$TMP_EXT -i $SL_INPUT -i TMPshadowmask.png -i TMPbezel.png -filter_complex \
		"[0][1]blend=all_mode='multiply':all_opacity=${SL_ALPHA}[a],\
[a][2]blend=all_mode='multiply':all_opacity=${OVL_ALPHA}[b],\
[b][3]blend=all_mode='multiply',\
lutrgb='r=clip(val*${BRIGHTEN},0,${RNG}-1):\
g=clip(val*${BRIGHTEN},0,${RNG}-1):\
b=clip(val*${BRIGHTEN},0,${RNG}-1)'" \
$TMP_OUTPARAMS TMPstep03.$TMP_EXT

else

	echo ""
	echo "Step03:"
	ffmpeg -hide_banner -loglevel $LOGLVL -stats -y\
	-i TMPstep02.$TMP_EXT -i TMPshadowmask.png -i TMPbezel.png -filter_complex \
		"[0][1]blend=all_mode='multiply':all_opacity=${OVL_ALPHA}[b],\
[b][2]blend=all_mode='multiply',\
lutrgb='r=clip(val*${BRIGHTEN},0,${RNG}-1):\
g=clip(val*${BRIGHTEN},0,${RNG}-1):
b=clip(val*${BRIGHTEN},0,${RNG}-1)'" \
$TMP_OUTPARAMS TMPstep03.$TMP_EXT
fi

if [ "$?" != "0" ]
then
  exit 1
fi


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Detect crop area; crop, rescale, monochrome (if set), vignette, pad, set sar/dar #
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#

ffmpeg -hide_banner -y \
	-f lavfi -i "color=c=#ffffff:s=${PX}x${PY}"	-i TMPbezel.png \
	-filter_complex "[0]format=rgb24 ${LENSC}[crt]; [crt][1]overlay, cropdetect=limit=0:round=2"\
	-frames:v 3 -f null - 2>&1 | grep "crop=" > TMPcrop

if [ "$?" != "0" ]
then
  exit 1
fi

CROP_STR=$(cat TMPcrop | awk -F"crop=" '{print $2}' | awk '{print $1}')

#for /f "tokens=*" %%a IN (TMPcrop) do set CROPTEMP=%%a
#for %%a IN (%CROPTEMP%) do set CROP_STR=%%a

if [ ! -z "$TEXTURE_OVL" ]
then
  if [ "$TEXTURE_OVL" == "paper" ]
  then
    TEXTURE_STR="[nop];movie=TMPtexture.png,format=${RGBFMT}[paper];[nop][paper]blend=all_mode='multiply':eof_action='repeat'"
  fi
  if [ "$TEXTURE_OVL" == "lcdgrain" ]
  then
    TEXTURE_STR=",format=${KLUDGEFMT},split[og1][og2];\
movie=TMPtexture.png,format=${KLUDGEFMT}[lcd];\
[lcd][og1]blend=all_mode='vividlight':eof_action='repeat'[notquite];\
[og2]limiter=0:110*${RNG}/256[fix];\
[fix][notquite]blend=all_mode='lighten':eof_action='repeat', format=${RGBFMT}"
  fi
fi

echo $TEXTURE_STR

echo ""
echo "Output:"

#echo CROP_STR $CROP_STR
#echo MONO_STR1 $MONO_STR1
#echo OX $OX OY $OY OMARGIN $OMARGIN
#echo OFILTER $OFILTER
#echo SWSFLAGS $SWSFLAGS
#echo RGBFMT $RGBFMT
#echo MONO_STR2 $MONO_STR2
#echo VIGNETTE_STR $VIGNETTE_STR
#echo TEXTURE_STR $TEXTURE_STR
#echo FIN_MATRIXSTR $FIN_MATRIXSTR
#echo FIN_OUTPARAMS $FIN_OUTPARAMS
#echo OUTFILE $OUTFILE

ffmpeg -hide_banner -loglevel $LOGLVL -stats -y -i TMPstep03.${TMP_EXT} -filter_complex "crop=${CROP_STR},\
format=gbrp16le,\
lutrgb='r=gammaval(2.2):g=gammaval(2.2):b=gammaval(2.2)',\
${MONO_STR1}\
scale=w=${OX}-${OMARGIN}*2:h=${OY}-${OMARGIN}*2:force_original_aspect_ratio=decrease:flags=${OFILTER}+${SWSFLAGS},\
lutrgb='r=gammaval(0.454545):g=gammaval(0.454545):b=gammaval(0.454545)',\
format=gbrp16le,\
format=${RGBFMT},\
${MONO_STR2}\
setsar=sar=1/1\
${VIGNETTE_STR}\
pad=${OX}:${OY}:-1:-1:black" \
${TEXTURE_STR} ${FIN_MATRIXSTR} ${FIN_OUTPARAMS} ${OUTFILE}

if [ "$?" != "0" ]
then
  exit 1
fi

#++++++++++#
# Clean up #
#++++++++++#

rm -f TMPbezel.png
rm -f TMPscanline?.*
rm -f TMPshadow*.png
rm -f TMPtexture.png
rm -f TMPgrid.png
rm -f TMPstep0?.*
rm -f TMPbloom.*
rm -f TMPcrop

echo ""
echo "------------------------"
echo Output file: $OUTFILE
echo Started: $FFSTART
echo Finished: $(date)
echo ""
exit 0
