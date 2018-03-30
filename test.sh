#!/bin/bash

# Mateusz Dudziński
# IPP, 2018L Task: "Maraton filmowy".

DIRECTORY=./tests
PROGRAM=./bin/program

CHECK_FOR_MEM_LEAKS=true

MAX_ALLOCATED_SIZE=0
MAX_TIME=0.0

PROGRAM_OUT=`mktemp`
PROGRAM_ERR=`mktemp`
PROGRAM_VALG=`mktemp`

yesNoConfirm() {
    read -s -n1 -p "$1 [Y/n]?" USER_INPUT
    echo ""
    if [ "$USER_INPUT" = "n" ] || [ "$USER_INPUT" = "N" ] \
           || [ "$USER_INPUT" = "no" ] || [ "$USER_INPUT" = "No" ]; then
        false
    else
        true
    fi
}

# Check if specyfied program and direcotory are valid:
if [ ! -f $PROGRAM ]; then
    echo $PROGRAM " does not exist. Exitting..."
    exit 2
fi
if [ ! -d $DIRECTORY ]; then
    echo $DIRECTORY " does not exist. Exitting..."
    exit 2
fi

for i in $(ls $DIRECTORY | egrep -i '*.in'); do

    # Alias these variables to make it more readable.
    INPUT=$DIRECTORY/$i
    OUTPUT=$DIRECTORY/${i%in}out
    ERR=$DIRECTORY/${i%in}err

    echo -e "Doing test on file: \e[1m$INPUT\e[0m"

    # Check if correspoing .out and .err files exists.
    if [ ! -f $OUTPUT ] || [ ! -f $ERR ]; then
        # TODO: Message about no corresponding files!
        echo "No corresponding files for test: $INPUT! Skipping..."
        continue
    fi

    # TODO: Also it makes valgr output. Add info about it! Scripting test makes
    # two temporary files $PROGRAM_OUT and $PROGRAM_ERR to store program output.

    TIME_START=$(date +%s.%N)
    $PROGRAM < $INPUT > $PROGRAM_OUT 2> $PROGRAM_ERR
    PROGRAM_EXIT_CODE=$?
    TIME_END=$(date +%s.%N)
    TIME_DIFF=$(echo "$TIME_END - $TIME_START" | bc | awk '{printf "%f", $0}')

    # bash dont do great job when it comes to compare floating point numbers...
    if (( `echo "$TIME_DIFF > $MAX_TIME" | bc` )); then
        MAX_TIME="$TIME_DIFF"
        MAX_TIME_FILE=$INPUT
    fi

    if [ "$PROGRAM_EXIT_CODE" -ne "0" ]; then
        echo -n "Program execution failed with error code: "
        echo -e "\e[1;31m$PROGRAM_EXIT_CODE\e[0m"
        # TODO: Continue testing?
        continue
    else
        echo -e "Program execution            \e[1;32mOK\e[0m (Time: ${TIME_DIFF} s)"
    fi

    # TODO: Collapse differs!!!
    echo -n "Comparing standard output... "
    if diff $PROGRAM_OUT $OUTPUT &> /dev/null; then
        echo -e "\e[1;32mOK\e[0m"
    else
        echo -e "\e[1;31mDIFFERS!\e[0m"
        if yesNoConfirm "Show diff?"; then
            diff --color $PROGRAM_OUT $OUTPUT
            # Ask user to abort testing.
            if ! yesNoConfirm "Continue?"; then
                exit 1
            fi
        fi
    fi

    echo -n "Comparing stderr output...   "
    if diff $PROGRAM_ERR $ERR &> /dev/null; then
        echo -e "\e[1;32mOK\e[0m"
    else
        echo -e "\e[1;31mDIFFERS!\e[0m"
        if yesNoConfirm "Show diff?"; then
            diff --color $PROGRAM_ERR $ERR
            # Ask user to abort testing.
            if ! yesNoConfirm "Continue?"; then
                exit 1
            fi
        fi
    fi

    # Unfortunetly we have to run a program again to look for memory
    # leaks. Note: valgrind will return 1 if there are leaks, 0 when they are
    # not. This differs from the default, when valgrind just returns programs
    # exit code.
    if $CHECK_FOR_MEM_LEAKS; then
        echo -n "Checking for memory leaks... "

        valgrind --leak-check=full --log-file="$PROGRAM_VALG" --error-exitcode=1 $PROGRAM < $INPUT &> /dev/null
        VALGR_EXIT_CODE=$?

        USAGE_INFO=`cat $PROGRAM_VALG | grep 'total heap usage'`
        regex="==[0-9]+==\s+total heap usage: ([0-9,]+) allocs, ([0-9,]+) frees, ([0-9,]+) bytes allocated"
        if [[ $USAGE_INFO =~ $regex ]]; then
            ALLOCATED_SIZE=`echo ${BASH_REMATCH[3]} | tr --delete ,`
            if [ $ALLOCATED_SIZE -ge $MAX_ALLOCATED_SIZE ];then
                MAX_ALLOCATED_SIZE="$ALLOCATED_SIZE"
                MAX_ALLOCATION_FILE="$INPUT"
            fi
        else
            exit 2
        fi

        if [ "$VALGR_EXIT_CODE" -eq "0" ]; then
            echo -ne "\e[1;32mOK\e[0m"
            echo " (Total allocated: $ALLOCATED_SIZE B)"
        else
            echo -e "\e[1;31mLEAKS DETECTED!\e[0m"
            if yesNoConfirm "Show Valgrind output?"; then
                cat $PROGRAM_VALG
                if ! yesNoConfirm "Continue?"; then
                    exit 1
                fi
            fi
        fi
    fi
done

# cleanup:
rm $PROGRAM_OUT
rm $PROGRAM_ERR
rm $PROGRAM_VALG


echo "Testing done."
echo "Max time: $MAX_TIME_FILE ($MAX_TIME s)."
echo "Max allocation at file: $MAX_ALLOCATION_FILE ($MAX_ALLOCATED_SIZE B)."
