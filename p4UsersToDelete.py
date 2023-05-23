import requests
import re
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
import urllib3
import subprocess
import os

#=================================================================================
#Defining the Retry strategy for when there are issues getting web content
#and configuring the session
retry_strategy = Retry(
    total=5,
    backoff_factor=2,
    status_forcelist=[429, 500, 502, 503, 504],
    allowed_methods=["GET"]
)
adapter = HTTPAdapter(max_retries=retry_strategy)
http = requests.Session()
http.mount("https://", adapter)
http.mount("http://", adapter)
urllib3.disable_warnings()

#=================================================================================
#Declaring variables
output=""
my_files=""
PLUMdeletedUsers = []
PLUMactiveUsers = []
PerforceActiveUsers = []
UsersToDelete = []
FinalUsersToDelete = []
ListOfFiles = []

#================================================================================
#Calling "PullFromApex" api from PLUM to get the list of active and deleted users
try:
  r = http.get('https://<APEX_HOST>/apex/apex_nnn/plum/PullFromApex.txt')
  r.raise_for_status()
  resp = r.text
except requests.exceptions.RequestException as err:
  output += "\n" "Oops, something happened when trying to get a response from PLUM-APEX: " + str(err)

#=========================================================================================
#Creating list of the users that are supposed to be deleted or are already deleted in PLUM
resp = resp.replace('"','')
for line in resp.splitlines():
    if line.startswith("DELETED"):
        if re.findall('.*?,(.*?),', line):
            line = re.findall('.*?,(.*?),', line)[0]
            PLUMdeletedUsers.append(line)

#=================================================================================
#Creating list of the users that are supposed to be active in PLUM
for line in resp.splitlines():
    if line.startswith("USER"):
        if re.findall('.*?,(.*?),', line):
            line = re.findall('.*?,(.*?),', line)[0]
            PLUMactiveUsers.append(line)

#=================================================================================
#Making sure there are no "problematic" users, which means that they are tagged
#as active and deleted at the same time in the DB
PLUMdeletedUsers_final = [x for x in PLUMdeletedUsers if x not in PLUMactiveUsers]

#====================================================================================
#Now that the PLUM part is complete, we have to compare the resultant list of deleted
#users, with the Perforce active users
output1 = subprocess.check_output(["/usr/local/bin/p4", "users"])
for word in output1.decode('utf-8').split('\n'):
    if re.findall('(.*?)\s', word):
        word = re.findall('(.*?)\s', word)[0]
        PerforceActiveUsers.append(word)

#====================================================================================
#This comparison will show which users are marked for deletion in PLUM but are not
#yet deleted in Perforce, which means those users potentially have open/shelved files.
for list in PLUMdeletedUsers_final:
    if list in PerforceActiveUsers:
        UsersToDelete.append(list)

#====================================================================================
#Printing the list of users about to be deleted
#print(UsersToDelete)

#UsersToDelete = ["kgonzale", "lrojas", "lzhang"]

#Call the user deletion script to close opened/shelved files
for user in UsersToDelete:
    p = subprocess.run(["/opt/apps/bin/p4userdeletion.sh", user, "yes"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if p.returncode == 0:
        FinalUsersToDelete.append(user)

#proceed to notify the team about the user deleted and send the output files via email
for user in FinalUsersToDelete:
    my_files = ""
    path = f"/opt/apps/perforce/PerDeletion/{user}"
    if(os.path.exists(path)):
        for file in os.listdir(path):
            my_files += f"-a {path}/{file} "
        #print(my_files)
        if my_files:
            subject = f"{user}: Perforce & PLUM. Pre-user deletion - Closed opened files"
            body = f"Automated job to close opened/shelved files for user: {user}"
            toaddr = "alerts@<HOST>.com"
            cmd = "mail -s " + subject + " " + my_files  + toaddr

            os.system(f"echo \"{body}\" | mail -s \"{subject}\" {my_files} {toaddr}")
exit(0)
