#!/bin/bash
#TESTRUNSTART=%time%
TESTRUNSTART=$(date +%s.%N)

echo rm *OLD* 2> /dev/null

for filename in *out.*; do 
    echo mv "${filename}" "${filename//\.*/}-OLD.${filename//?*\./.}"
done

pushd ..
for filename in test-suite/??.*; do 
    EXTENSION=${filename//?*\./.}
    BASENAME=${filename//\.*/}
    echo ./ffcrt.sh ${filename//\.mp4/cfg.cfg} ${filename} ${BASENAME}-out${EXTENSION}
done
popd
ENDRUN=$(date +%s.%N)

echo "TOTAL FOR ALL TESTS - "
echo "Started:     ${TESTRUNSTART} Seconds"
echo "Finished:    ${ENDRUN} Seconds"
echo "Total:       $( echo "$end - $start" | bc -l ) Seconds"
