# Proxy Action Client Scripts
Provides scripts to perform actions on a device via the public device API.

## hup-device.sh
Perform a host OS update via the device API. This command works similarly to the balenaCLI command `balena device os-update`. However, it executes the update via the device API rather than the Node SDK.

The example below includes the HTTP response, as well as output from following the update to completion. In this example we first define the API token, but you can explicitly pass this value on the command line as well. Run `hup-device.sh -h` to see all of the options.


```
$ export API_TOKEN="$(cat < ${BALENARC_DATA_DIRECTORY}/token)"

$ ./hup-device.sh -u 3a6c9251d533e064f34ca924458d7e23 \
   -v "6.0.10" -r -f
[INFO] code: 202
[INFO] response: {"status":"triggered","lastRun":1724944519887,"parameters":{"target_version":"6.0.10"},"action":"resinhup"}

  Time       Status     Pct       Detail             
--------  ------------  ---  ------------------------
11:15:20  Idle                                       
11:15:23  configuring    50  Running OS update       
11:16:44  configuring    95  Running supervisor updat
11:17:00  configuring   100  Update successful, reboo
11:17:09  configuring   100  Reboot in progress      
11:18:19  Idle                                       
```

