#!/usr/bin/env bash
#Title			: alc_proj_checker.sh
#Usage			: bash alc_proj_checker.sh projectX
#Author			: pmorvalho
#Date			: February 12, 2023
#Description	        : Checks if some student's project submission is consistent with a set of IO tests.
#Notes			: 
# (C) Copyright 2023 Pedro Orvalho.
#==============================================================================

git config --global user.name "GitSEED"
git config --global user.email "gitseed@arsr.inesc-id.pt"
git checkout master
git fetch origin master
git stash
git merge -s recursive -X theirs origin/master	       
git pull
initial_dir=$(pwd)

chmod +x *.py

# the students' git identification e.g. group1 or ist1XXXXX
stu_id=$(echo $initial_dir | rev | cut -d '/' -f 1 | rev)
# which project is being evaluated e.g. project1
project=$(echo $initial_dir | rev | cut -d '/' -f 2 | rev)
# the course (e.g. IAED23) which is the main group (root) in GitLab
course=$(echo $initial_dir | rev | cut -d '/' -f 3 | rev)

source /home/alc/config.sh $project

# the number of commits/changes made by the student being evaluated on the yml script (CI script).
faculty_commits=$(git log  --author=$FACULTY_ID --format='%an' .gitlab-ci.yml | wc -l)
echo "Yml modified by the faculty $faculty_commits times"
yml_modifications=$(git log --format='%an' .gitlab-ci.yml | wc -l)
echo "Yml modified $yml_modifications times in total"
number_of_commits=$(python3 -c "print(str(int('$yml_modifications')-int('$faculty_commits')))")
echo "Number of times $stu_id modified the yml: $number_of_commits"


if [[ $number_of_commits -gt 0  ]]; then
    echo "[-Students should not alter the YAML file (.yml) in the repository. Modifying it will result in an automatic loss of access to the repository.-]"  > $FEEDBACK_DIR/$stu_id/README.md
    echo >> $FEEDBACK_DIR/$stu_id/README.md
    echo "[-Please contact the course's faculty.-]" >>  $FEEDBACK_DIR/$stu_id/README.md
    cd $FEEDBACK_DIR/$stu_id
    git add README.md
    git commit -m "Student's access blocked. Please contact the course's faculty."
    git push -f
    cd $HOME
    # this will restrict the student's access from DEVELOPER to GUEST, so the student cannot modify the git repo.
    python3 gitlab_manager.py -rss $stu_id $project
    exit 1
fi

number_of_submissions=$(git log --format='%an' *.py | wc -l)
number_of_submissions=$(python3 -c "print(str(int('$number_of_submissions')-1))")

if [[ $(git log -1 --pretty=format:'%an') == $FACULTY_ID ]]; then
    echo "This was a faculty update on the student's git."
    exit 0
fi

echo
echo
echo
echo "Currently running "$initial_dir

#commit_date=$(git log --date=iso-strict -1 --format=%cd)
#last_commit_date=$(git log --date=iso-strict -2 --format=%cd | tail -n1)

incorrect=0
correct=0
total=0	

# previous second last
last_commit_date=$(python3 $HOME/commits_manager.py -p $project -g $stu_id)
commit_date=$(python3 $HOME/commits_manager.py -p $project -g $stu_id --update)

eval_name=$(date +%s)
touch Evaluation-$eval_name".md"
echo "Evaluating code submitted at: $commit_date"
echo | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"
echo "# Evaluation" | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"


echo ${commit_date/%\.*/} | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"

hash_code=$(git log --pretty=format:'%h' -n 1)


echo "Commit: "$hash_code | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"
echo "Code pushed to $stu_id's git [repository](https://gitlab.rnl.tecnico.ulisboa.pt/$course/$project/$stu_id/-/tree/master)." | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"
echo "The evaluated code can be found [here](code-evaluated.tar)." | tee -a Evaluation-$eval_name".md"
echo | tee -a Evaluation-$eval_name".md"

if [[ $last_commit_date == "" ]]; then
    min_delta=$((MINUTES_BETWEEN_SUBMISSIONS+100))
else
    min_delta=$(python3 -c "from datetime import datetime; d1 = datetime.fromisoformat('$commit_date'); d2 = datetime.fromisoformat('$last_commit_date'); print(str(int(divmod((d1-d2).total_seconds(), 60)[0])))")
    min_delta=$((min_delta))
fi
next_sub=$(python3 -c "from datetime import datetime, timedelta; d1 = datetime.fromisoformat('$commit_date'); print(str(d1 + timedelta(minutes=int('$MINUTES_BETWEEN_SUBMISSIONS'))))")
next_sub=${next_sub/%\.*/}
#echo "Minutes between submissions $min_delta"
if [[ ( $min_delta -lt $MINUTES_BETWEEN_SUBMISSIONS ) && ( $last_commit_date != "" ) ]];
then
    echo | tee -a Evaluation-$eval_name".md"
    echo "Students must [-wait $MINUTES_BETWEEN_SUBMISSIONS minute(s)-] between their submissions." | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    next_sub=${next_sub/%\+*/}
    echo "Please do not resubmit your code until [- $next_sub-] @ $CITY." | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo "IGNORING:: $stu_id did not respect the cool-down period. New commit: $commit_date. Last commit: $last_commit_date. Delta: $min_delta. They need to wait $MINUTES_BETWEEN_SUBMISSIONS minutes."
else
    touch Evaluation-$eval_name".md"
    # prog_name=$(ls *.c | tail -n 1)
    wdir=$(pwd)
    mkdir -p $wdir"/your_outputs"
    
    # gcc -O3 -Wall -Wextra -Werror -ansi -pedantic -lm *.c -o proj.out 2> compilation_errors.err
    
    ## check forbidden libraries. Cannot use qsort, extern or goto
    
    # grep 'qsort\|extern\|goto' -s *.c *.h > forbidden_words.err
    
    if [[ -s compilation_errors.err ]]; then
	echo "## [- Compile Time Error-]." | tee -a Evaluation-$eval_name".md"
	correct=0
	incorrect=0
    else
	if [[ -s forbidden_words.err ]]; then
	    echo "## [- Forbidden Word Usage -]." | tee -a Evaluation-$eval_name".md"
	else
	    # for t in $(find $HOME/tests/$project/*.in -maxdepth 0 -type f);
	    mkdir safeexec-outputs
	    for t in $(find $HOME/tests/$project/*.ttp -maxdepth 0 -type f);		     
	    do
		t_id=$(echo $t | rev | cut -d '/' -f 1 | rev)
		# t_id=$(echo $t_id | sed -e "s/\.in//")
		t_id=$(echo $t_id | sed -e "s/\.ttp//")
		total=$((total+1))		
		/home/alc/safeexec/safeexec --cpu $TIMEOUT --clock $((TIMEOUT+10)) --mem $MEMOUT --error safeexec-outputs/$t_id.error --usage safeexec-outputs/$t_id.out --exec $project".py" < $t > "your_outputs/"$t_id".out"
		status=$(head -n1 safeexec-outputs/$t_id.out)
		if [[ $status == "OK" ]]; then
		    $HOME/ttp-checker/ttp-checker $t "your_outputs/"$t_id".out" > "your_outputs/"$t_id".check"	    
		    if [[ $(cat "your_outputs/"$t_id".check") == "OK" ]]; then
			if [[ $(head -n1 "your_outputs/"$t_id".out") == $(head -n1 $HOME/"tests/"$project"/"$t_id".out") ]];
			then
			    correct=$((correct+1))
			    echo "## Test $total: [+ Accepted+]." | tee -a Evaluation-$eval_name".md"
			    continue;
			else
			    incorrect=$((incorrect+1))
			    echo "## Test $total: [- Non optimal value-]." | tee -a Evaluation-$eval_name".md"			    
			    continue;
			fi
		    else
			incorrect=$((incorrect+1))
			d=$(diff -w -B "your_outputs/"$t_id".out" $HOME/"tests/"$project"/"$t_id".out")	    
			if [[ $d == "" ]];
			then
			    echo "## Test $total: [- Presentation Error-]." | tee -a Evaluation-$eval_name".md"
			    continue;
			fi
			echo "## Test $total: [- Wrong Answer-]." | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"			
			echo "### Checker's output:" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			cat "your_outputs/"$t_id".check" >> Evaluation-$eval_name".md"	       	
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			if [[ $SHOW_OUTPUT == 0 ]];
			then
			    echo | tee -a Evaluation-$eval_name".md"
			    continue
			fi
		    fi
		    if [[ (( $SHOW_ONLY_ONE_INCORRECT_OUTPUT == 1 && $incorrect == 1 ) || $SHOW_ONLY_ONE_INCORRECT_OUTPUT == 0 )]]; then
			echo "- Input:" | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			cat $HOME/"tests/"$project"/"$t_id".in" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "- Your Output:" | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			cat "your_outputs/"$t_id".out" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "- Expected Output:" | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			cat $HOME/"tests/"$project"/"$t_id".out" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
		    fi
		else
		    incorrect=$((incorrect+1))
		    echo "## Test $total: [- $status-]." | tee -a Evaluation-$eval_name".md"
		    echo | tee -a Evaluation-$eval_name".md"
		    if [[ -s safeexec-outputs/$t_id.error ]]; then
			echo | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"			
			echo "### Error:" | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo | tee -a Evaluation-$eval_name".md"
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
			# the next command censors all the paths from the safeexec's error file
			cat safeexec-outputs/$t_id.error | sed 's/[..]*\/.*\//\//g' >> Evaluation-$eval_name".md"			
			echo "\`\`\`" | tee -a Evaluation-$eval_name".md"	       		       
		    fi
		fi
	    done
	    echo | tee -a Evaluation-$eval_name".md"
	    echo | tee -a Evaluation-$eval_name".md"
	    echo "## Number of passed tests: "$correct"/"$total | tee -a Evaluation-$eval_name".md"
	fi
    fi
    echo | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo "Your code will not be reevaluated if you submit before $next_sub @ $CITY. You need to wait $MINUTES_BETWEEN_SUBMISSIONS minute(s)." | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo
fi



if [[ -s compilation_errors.err ]]; then
    echo | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo "- Compiler Output:" | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
    cat compilation_errors.err >> Evaluation-$eval_name".md"
    echo | tee -a Evaluation-$eval_name".md"
    echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
else
    if [[ -s forbidden_words.err ]]; then
	echo | tee -a Evaluation-$eval_name".md"
	echo | tee -a Evaluation-$eval_name".md"
	echo "- Check Output:" | tee -a Evaluation-$eval_name".md"
	echo | tee -a Evaluation-$eval_name".md"
	echo | tee -a Evaluation-$eval_name".md"
	echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
	cat forbidden_words.err >> Evaluation-$eval_name".md"
	echo | tee -a Evaluation-$eval_name".md"
	echo "\`\`\`" | tee -a Evaluation-$eval_name".md"
    fi
fi

first_commit=$(git log --date=iso-strict --format=%cd | tail -1)
competition_days=$(python3 -c "from datetime import datetime; d1 = datetime.fromisoformat('$commit_date').replace(tzinfo=None); d2 = datetime.fromisoformat('$first_commit').replace(tzinfo=None); print(str(int((d1-d2).days)))")


echo "Submitting group $stu_id evaluation for $project."
cat $HOME/$project/README.md > $FEEDBACK_DIR/$stu_id/README.md
cat Evaluation-$eval_name".md" >> $FEEDBACK_DIR/$stu_id/README.md
git archive --format=tar -o $FEEDBACK_DIR/$stu_id/code-evaluated.tar HEAD
# cp README.md $HOME/iaed_evaluations/$course@$project@$stu_id.md
cd $FEEDBACK_DIR/$stu_id
git checkout master
git pull
git add README.md code-evaluated.tar
git commit -m "$project has been evaluated!"
git push -f

cd $HOME
echo "Updating the course's dashboard with $stu_id scores: -g $stu_id -p $project -c $correct -i $incorrect -n $number_of_submissions -d $competition_days"
python3 dashboard_manager.py -g $stu_id -p $project -c $correct -i $incorrect -n $number_of_submissions -d $competition_days

cd $initial_dir

