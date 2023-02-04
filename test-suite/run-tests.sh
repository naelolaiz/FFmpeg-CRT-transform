#!/bin/bash
TESTRUNSTART=$(date +%s.%N)

echo rm *OLD* 2> /dev/null

for filename in *out.*; do 
    mv "${filename}" "${filename//\.*/}-OLD.${filename//?*\./.}"
done

pushd ..
for filename in test-suite/??.*; do 
    EXTENSION=${filename//?*\./.}
    BASENAME=${filename//\.*/}
    ./ffcrt.sh ${BASENAME}cfg.cfg ${filename} ${BASENAME}-out${EXTENSION}
done
popd
ENDRUN=$(date +%s.%N)

echo "TOTAL FOR ALL TESTS - "
echo "Started:     ${TESTRUNSTART} Seconds"
echo "Finished:    ${ENDRUN} Seconds"
