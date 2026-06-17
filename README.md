# docker-wrf

Build docker container images for running WRF.

Based on the original "wrf-container" created by Jared Lewis at Climate
Resource: https://github.com/climate-resource/docker-wrf.

## Requirements

[Docker](https://www.docker.com/) is required.
    
### Local development

For local testing, the docker image can be used to build the WRF image. 
This is a good way to test changes to the scripts. 

To build the docker image, run the following command:

```
docker build . -t wrf
```

If building on a Arm-based Mac, the following command should be used to target the correct platform.
Otherwise, the build will emulate the amd64 platform and take much longer.

```
docker build --build_arg PLATFORM=linux/arm64 . -t wrf
```
