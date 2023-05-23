#!/bin/bash

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/apps/plum

userToDelete=$1
automated=$2

display_usage() { 
	echo -e "*********************************************************************************"
	echo -e "---->This script must receive one argument." 
	echo -e "\n---->Usage:\n./p4userdeletion.sh [p4UserToDelete]\n" 
	echo -e "*********************************************************************************"
	}

# if less than two arguments supplied, display usage 
	if [ $# -ne 1 ]; then
		if [ $# -ne 2 ]; then
			echo "$#"
			display_usage
			exit 1
		fi
	fi 

#Location of the resultant files: /opt/apps/common/PerDeletion/$userToDelete/
outputPath=/opt/apps/perforce/PerDeletion/$userToDelete
port=1666
servers=('perforce' 'perforce2' 'perforce3')
userLoggedin=0

#checking IF p4 is able to find any user with the specified name:
if [[ $(p4 -s login $userToDelete | grep "User $userToDelete logged in." | wc -c) -eq 0 ]]; then
	echo -e "Perforce was not able to identify/login the user $userToDelete.  Please double-check if the user exists."
	echo -e "\t\tCommand used to confirm this: \"p4 login $userToDelete\" "
	exit 0
fi
p4 -s logout $userToDelete | sed "s/.*//" | sed "$ d" | sed "$ d"

if [ -d "$outputPath" ]; then
	if [[ -n $automated ]]; then
		exit 2
	else
		echo "The folder for this user already exist, if you continue it may override the existing files inside this folder."
		while true; do
			read -p "Do you want to proceed? (y/n): " yn
			case $yn in
				[Yy]* ) echo " ... Continuing ..."; break;;
				[Nn]* ) echo " ... Exiting ..."; exit;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	fi
else
	mkdir -p $outputPath/
fi

### First of all, let's look for opened files
echo -e "**************************************************" >> $outputPath/p4userdeletion.out
echo -e "************ Looking for Opened files ************" >> $outputPath/p4userdeletion.out
echo -e "**************************************************" >> $outputPath/p4userdeletion.out
for p4server in "${servers[@]}"
do
userLoggedin=0
	if [[ $(p4 -s -p $p4server:$port opened -u $userToDelete 2>&1 | grep -E 'Connect to server failed\; check \$P4PORT|Your session has expired|Perforce password \(P4PASSWD\) invalid or unset')  ]];then
		echo -e "$p4server: P4 Error (not script): \n$(p4 -s -p $p4server:$port opened -u $userToDelete 2>&1 | sed 's/^/\t\t\t\t\t/') " >> $outputPath/p4userdeletion.out

	elif [[ $(p4 -s -p $p4server:$port opened -u $userToDelete | grep "error: File(s) not opened anywhere") ]]; then
		echo -e "$p4server: Could NOT find Opened files" >> $outputPath/p4userdeletion.out
	
	elif [[ $(p4 -s -p $p4server:$port opened -u $userToDelete | grep -m 1 "info: //") ]]; then
		echo -e "$p4server: Found Opened files " >> $outputPath/p4userdeletion.out

		usedWorkspaces=( $(p4 -s -p $p4server:$port opened -u $userToDelete | sed -E "s/.*\@//" | sort -u | grep -v "exit: 0") )
		for currentWorkspace in "${usedWorkspaces[@]}"
		do
			usedChangelists=( $(p4 -p $p4server:$port changes -c $currentWorkspace | grep pending | awk '{print $2}') )
			for currentChangelist in "${usedChangelists[@]}"
			do
				if [[ $(p4 -p $p4server:$port describe -sS $currentChangelist | tail -n 2 | grep "...") ]]; then
					echo -e " ($currentWorkspace - $currentChangelist) Found Shelved files - Ignoring, will be handled later " >> $outputPath/p4userdeletion.out
				else
					if [ "$userLoggedin" -eq 0 ]; then
						temp_string=$(p4 -p $p4server:$port login $userToDelete)
                                        	echo -e " $temp_string " >> $outputPath/p4userdeletion.out
						userLoggedin=1
					fi					
					temp_string=$(p4 -p $p4server:$port revert -C $currentWorkspace -a -c $currentChangelist)
							echo -e " ($currentWorkspace - $currentChangelist) Reverting files: " >> $outputPath/p4userdeletion.out
			                echo -e " ($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out
					temp_string=$(p4 -p $p4server:$port -c $currentWorkspace -u $userToDelete change -d $currentChangelist)
					echo -e " ($currentWorkspace - $currentChangelist) Deleting changelist: " >> $outputPath/p4userdeletion.out
					echo -e " ($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out

					#LINES TO SOLVE ERRORS LIKE: Change 42530406 has 1 open file(s) associated with it and can't be deleted.
					changeListsIDS=( $(p4 -s -p $p4server:$port opened -u $userToDelete | sed "/edit default change/d" | sed "s/.*change //" | sed "s/ .*//" | sed  "$ d" | sort -u) )
					for changeListID in "${changeListsIDS[@]}"
					do
						if [ "$currentChangelist" = "$changeListID" ]; then
							temp_string=$(p4 -s -p $p4server:$port revert -C $currentWorkspace -c $currentChangelist //...)
								echo -e " ($currentWorkspace - $currentChangelist) Reverting problematic files (if any): " >> $outputPath/p4userdeletion.out
			         	       echo -e " ($currentWorkspace - $currentChangelist) $temp_string  " | sed 's/error: \/\/... - file(s) not opened on this client./ /g'  | sed 's/error: \/\/... - file(s) not opened in that changelist./ /g' >> $outputPath/p4userdeletion.out
						fi
					done
				fi
			done

			#ALWAYS looking for opened files on the "default" changelist
			openedInDefault=( $(p4 -s -p $p4server:$port opened -u $userToDelete | grep "edit default") )
			if [[ $(p4 -s -p $p4server:$port opened -u $userToDelete | grep "edit default") ]];then
				echo -e "Found Open files on the default changelist... Closing them... " >> $outputPath/p4userdeletion.out
                                temp_string=$(p4 -p $p4server:$port revert -C $currentWorkspace -a -c default)
								echo -e " ($currentWorkspace - Default) Reverting default changelist: " >> $outputPath/p4userdeletion.out
                                echo -e " ($currentWorkspace - Default) $temp_string " >> $outputPath/p4userdeletion.out
			fi
		done	
	else
		echo -e "$p4server:SOMETHING WENT WRONG. " >> $outputPath/p4userdeletion.out
	fi

	if [ "$userLoggedin" -eq 1 ]; then
		temp_string=$(p4 -p $p4server:$port logout $userToDelete)
			echo -e "$p4server: $temp_string " >> $outputPath/p4userdeletion.out
			userLoggedin=0
	fi
done


### Now let's look for shelved files
echo -e "\n\n**************************************************" >> $outputPath/p4userdeletion.out
echo -e "*********** Looking for Shelved files ************" >> $outputPath/p4userdeletion.out
echo -e "**************************************************" >> $outputPath/p4userdeletion.out
for p4server in "${servers[@]}"
do
userLoggedin=0
	if [[ $(p4 -s -p $p4server:$port -u perforce changes -u $userToDelete -s shelved 2>&1 | grep -E 'Connect to server failed\; check \$P4PORT|Your session has expired|Perforce password \(P4PASSWD\) invalid or unset')  ]];then
                echo -e "$p4server: P4 Error (not script): \n$(p4 -s -p $p4server:$port -u perforce changes -u $userToDelete -s shelved 2>&1 | sed 's/^/\t\t\t\t\t/') " >> $outputPath/p4userdeletion.out

	elif [[ $(p4 -s -p $p4server:$port -u perforce changes -u $userToDelete -s shelved 2>&1 | grep "exit: 1") ]]; then	
		temp_string=$(p4 -s -p $p4server:$port -u perforce changes -u $userToDelete -s shelved)
                echo -e "$p4server: P4 Error (not script): \n\n$temp_string " >> $outputPath/p4userdeletion.out

        elif [[ $(p4 -s -p $p4server:$port -u perforce changes -u $userToDelete -s shelved | grep -m 1 "info:") ]]; then
                echo -e "$p4server: Found Shelved files " >> $outputPath/p4userdeletion.out
		
		usedWorkspaces=( $(p4 -s -p $p4server:$port changes -u $userToDelete -s shelved | grep -v "exit: 0" | sed -E "s/.*\@//" | awk '{print $1}'| sort -u ) )
        for currentWorkspace in "${usedWorkspaces[@]}"
		do
			workspaceChanged=0

			usedChangelists=( $(p4 -p $p4server:$port changes -c $currentWorkspace | grep pending | awk '{print $2}') )
            for currentChangelist in "${usedChangelists[@]}"
            do	
				if [ "$workspaceChanged" -eq 0 ]; then
					temp_string=$(p4 -p $p4server:$port client -o $currentWorkspace | sed -E 's/^Host:[[:space:]].*/Host:/' | p4 -p $p4server:$port client -i -f)
					echo -e "Removing Host from Workspace: $temp_string " >> $outputPath/p4userdeletion.out
                    	temp_string=$(p4 -p $p4server:$port client -o $currentWorkspace | sed -E "s/^Root:[[:space:]].*/Root:   \/opt\/apps\/perforce\/PerDeletion\/$userToDelete\/perfExport/" | p4 -p $p4server:$port client -i -f)
                       		echo -e "Changing the Workspace root to: $outputPath/perfExport/  Status: $temp_string" >> $outputPath/p4userdeletion.out
					workspaceChanged=1
				fi

				temp_string=$(mkdir -p $outputPath/perfExport; ls -la $outputPath/ | grep perfExport)
				echo -e "($currentWorkspace - $currentChangelist) Creating directory to save the shelved files info: ($outputPath/perfExport/)" >> $outputPath/p4userdeletion.out
                echo -e "($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out

                temp_string=$(p4 -p $p4server:$port describe -S $currentChangelist > $outputPath/perfExport/$userToDelete.$currentChangelist.txt; ls -la $outputPath/perfExport/ | grep $userToDelete.$currentChangelist.txt)
				echo -e "($currentWorkspace - $currentChangelist) Creating .txt file to output metadata of shelved files: " >> $outputPath/p4userdeletion.out
                echo -e "($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out

                listOfShelvedFiles="$(p4 -p $p4server:$port describe -sS $currentChangelist | grep "... //" | cut -c 5- | sed -E "s/\#.*//" | sed 's/.*/ "&"/' | tr -d '\n' | rev | cut -c 1- | rev | sed 's/^.//')"

				if [ "$userLoggedin" -eq 0 ]; then
					temp_string=$(p4 -p $p4server:$port login $userToDelete)
					echo -e "$temp_string " >> $outputPath/p4userdeletion.out
					userLoggedin=1
				fi

				temp_string="p4 -s -p $p4server:$port -c $currentWorkspace -u $userToDelete revert "
				echo -e "($currentWorkspace - $currentChangelist) Reverting Shelved Files:" >> $outputPath/p4userdeletion.out
				echo -n "($currentWorkspace - $currentChangelist) " >> $outputPath/p4userdeletion.out; eval $temp_string $listOfShelvedFiles >> $outputPath/p4userdeletion.out

				temp_string="p4 -s -p $p4server:$port -c $currentWorkspace -u $userToDelete unshelve -s $currentChangelist -f -c $currentChangelist -Af "
				echo -e "($currentWorkspace - $currentChangelist) Unshelving Files:" >> $outputPath/p4userdeletion.out
				echo -n "($currentWorkspace - $currentChangelist) " >> $outputPath/p4userdeletion.out; eval $temp_string $listOfShelvedFiles >> $outputPath/p4userdeletion.out

				temp_string=$(cd $outputPath/; zip -r $userToDelete.$currentChangelist.zip ./perfExport)
				echo -e "\Creating .zip file to compress .txt files: ">> $outputPath/p4userdeletion.out
				echo -e "\$temp_string " >> $outputPath/p4userdeletion.out

                temp_string="p4 -s -p $p4server:$port -c $currentWorkspace -u $userToDelete shelve --parallel=0 -d -Af -c $currentChangelist "
				echo -e "($currentWorkspace - $currentChangelist) Deleting Shelved Files:" >> $outputPath/p4userdeletion.out
				echo -n "($currentWorkspace - $currentChangelist) " >> $outputPath/p4userdeletion.out ; eval $temp_string $listOfShelvedFiles >> $outputPath/p4userdeletion.out

                                temp_string=$(p4 -p $p4server:$port revert -C $currentWorkspace -a -c $currentChangelist)
								echo -e "($currentWorkspace - $currentChangelist) Reverting Change List: " >> $outputPath/p4userdeletion.out
                                echo -e "($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out

                                temp_string=$(p4 -p $p4server:$port -c $currentWorkspace -u $userToDelete change -d $currentChangelist)
								echo -e "($currentWorkspace - $currentChangelist) Deleting Change List: " >> $outputPath/p4userdeletion.out
                                echo -e "($currentWorkspace - $currentChangelist) $temp_string " >> $outputPath/p4userdeletion.out

				temp_string=$(rm -rf $outputPath/perfExport)
                echo -e "Deleting $outputPath/perfExport Directory $temp_string " >> $outputPath/p4userdeletion.out
			
				#LINES TO SOLVE ERRORS LIKE: Change 42530406 has 1 open file(s) associated with it and can't be deleted.
				changeListsIDS=( $(p4 -s -p $p4server:$port opened -u $userToDelete | sed "/edit default change/d" | sed "s/.*change //" | sed "s/ .*//" | sed  "$ d" | sort -u) )
				for changeListID in "${changeListsIDS[@]}"
				do 
					if [ "$currentChangelist" = "$changeListID" ]; then
						echo -e "$p4server: Found more Opened files " >> $outputPath/p4userdeletion.out
						temp_string=$(p4 -s -p $p4server:$port revert -C $currentWorkspace -c $currentChangelist //...)
						echo -e " ($currentWorkspace - $currentChangelist) Reverting problematic files (if any): " >> $outputPath/p4userdeletion.out
						echo -e " ($currentWorkspace - $currentChangelist) $temp_string  " | sed 's/error: \/\/... - file(s) not opened on this client./ /g'  | sed 's/error: \/\/... - file(s) not opened in that changelist./ /g' >> $outputPath/p4userdeletion.out
					fi
				done
			done
		done
	else
		echo -e "$p4server: Could NOT find Shelved files" >> $outputPath/p4userdeletion.out
	fi

	if [ "$userLoggedin" -eq 1 ]; then
		temp_string=$(p4 -p $p4server:$port logout $userToDelete)
			echo -e "$p4server: $temp_string " >> $outputPath/p4userdeletion.out
			userLoggedin=0
	fi
done

echo "*******************************************************************************************" >> $outputPath/p4userdeletion.out
echo "*******************************************************************************************" >> $outputPath/p4userdeletion.out

if [[ -n $automated && $automated == "yes" ]]; then
  echo "Done! Executed via automation job" >> $outputPath/p4userdeletion.out
else
  echo "Done! Check the logs in the user folder: $outputPath/p4userdeletion.out"
fi

exit 0
