* create user homeassist, have its home dir in /opt/homeassist
* clone repo

* create python env

    python -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt

    ./Homeassist-Archive/fetchhomeassist.py > import.log 2>&1
