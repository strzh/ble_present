# ble_present
this is my first ruby program
This script used for detect BLE devices in home
if a devices not recorded in 10s, will be marked as off

for remote system execute the hcitool lescan, you need execute below command on remote system with the user
setcap 'cap_net_raw,cap_net_admin+eip' `which hcitool`
by default, it use root user,  the root user should use ssh key authorization.
