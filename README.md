# aks-flp-intsec
This is a set of scripts and tools use to generate a docker image that will have the aks-flp-intsec binary used to evaluate your AKS troubleshooting skill.

It uses the shc_script_converter.sh (build using the following tool https://github.com/neurobin/shc) to abstract the lab scripts on binary format and then the use the Dockerfile to pack everyting on a Ubuntu container with az cli and kubectl.

Any time the labs script require an update the github actions can be use to trigger a new build and push of the updated image. This will take care of building a new script binary as well as new docker image that will get pushed to the corresponding registry. The actions will get triggered any time a new release gets published.

Here is the general usage for the image and aks-flp-intsec tool:

Run in docker: `docker run -it sturrent/aks-flp-intsec:latest`

aks-flp-intsec tool usage:
```
$ aks-flp-intsec -h
aks-flp-intsec usage: aks-flp-intsec -l <LAB#> -u <USER_ALIAS> [-v|--validate] [-r|--region] [-h|--help] [--version]


Here is the list of current labs available:

*************************************************************************************
*        1. AKS faling to pull image from ACR
*        2. AKS identity issues
*        3. AKS cluster API access issue
*************************************************************************************

"-l|--lab" Lab scenario to deploy (3 possible options)
"-r|--region" region to create the resources
"--version" print version of aks-flp-intsec
"-h|--help" help info
```
