export MSYSTEM=UCRT64
export COMSPEC="C:\Windows\System32\cmd.exe"
source /etc/profile
cd /c/nifskope-src
make -j"$(nproc)" release 2>&1 | tail -40
