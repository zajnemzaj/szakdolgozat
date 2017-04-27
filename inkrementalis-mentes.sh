#!/bin/bash

#  Fájlnév: inkrementalis-mentes.sh
#  Leírás: Ssh-n keresztül weboldal inkrementális mentését elvégző script, daily, weekly, yearly mappákba.
#  Szerző: Dezső János

#  Szerver és azon levő adatbázis címének, felhasználó nevének és a szerveren lévő elérési út megadása
readonly SERVER_LOGIN="user@domain.nev"
readonly SERVER_PORT="23"
readonly SERVER_PATH="/var/www/domain.nev/www"
readonly BACKUP_DIR="alpha/$(basename $SERVER_PATH)"

#  Helyi elérési út
readonly LOCAL_BACKUP_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

#  A maximálisan tárolni kívánt napok és hetek száma
readonly DAYS_TO_STAY=7
readonly WEEKS_TO_STAY=8

#  Mai dátum és idő eltárolása
readonly DATE_TODAY="$(date +'%Y%m%d_%H%M')"

#  echo paranccsal használt színek megadása
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[1;34m'
readonly NC='\033[0m' # No Color

#  Elérési utak biztosítása a mentések számára
mkdir -p "$LOCAL_BACKUP_PATH/alpha"
mkdir -p "$LOCAL_BACKUP_PATH/daily"
mkdir -p "$LOCAL_BACKUP_PATH/weekly"
mkdir -p "$LOCAL_BACKUP_PATH/yearly"

#  Szinkronizálás
rsync -HavXx --delete -e "ssh -p $SERVER_PORT" $SERVER_LOGIN:${SERVER_PATH} ${LOCAL_BACKUP_PATH}/alpha --info=progress2 --stats > ${LOCAL_BACKUP_PATH}/rsyncstats.txt

#  Szinkronizált fájlok számának tárolása 
transferred_files=$(awk '/Number of regular files transferred/{print $NF}' ${LOCAL_BACKUP_PATH}/rsyncstats.txt)
echo -e "${BLUE}Szinkronizált fájlok száma: $transferred_files${NC}"

#  Függvény, átmásolja a backupot az argumentumnak megkapott mappába
function copy_backup {
    echo -e "${BLUE}\nÚj backup mentése a $1 mappába${NC}"
    mkdir -p "$LOCAL_BACKUP_PATH/$1/$DATE_TODAY"
    cp -al ${LOCAL_BACKUP_PATH}/$BACKUP_DIR/* $LOCAL_BACKUP_PATH/$1/$DATE_TODAY
    echo -e "${GREEN}Új backup mentve a $1 mappába.${NC}"
}

#  Függvény, mely törli $1 változóban definiált értéket meghaladó mentést
function remove_oldies {
        number_of_rows=$(wc -l < ${LOCAL_BACKUP_PATH}/idorend$2)
        if [[ $number_of_rows -gt $1-1 ]]; then
            toremove=$(tail -n+$1 ${LOCAL_BACKUP_PATH}/idorend$2 | head -n1)
            rm -rf $toremove
            echo -e "${RED}Régi mentés törölve a daily mappából: $toremove${NC}"
        fi
}

#  Függvény, mely eldönti, hogy szükséges-e menteni, és amennyiben igen, végrehajtja a $1 értéken kapott könyvtárra
function check_backup {
    cd "$LOCAL_BACKUP_PATH/$1"
    #  Fetétel, mely vizsgálja, hogy létezik-e már mentés
    if [ ! "$(ls $LOCAL_BACKUP_PATH/$1/* 2> /dev/null)" ]; then
        echo -e "${BLUE}\nElső mentés a $1 mappába:${NC}"
        copy_backup $1
    else
        #  Az "idorend" fájlba létrehoz egy listát csökkenő időrendbe a mentések fájlneveiből
        ls $LOCAL_BACKUP_PATH/$1/ -1 | sort -r > $LOCAL_BACKUP_PATH/idorend$1
        #  Eltárolja a legutolsó meglévő mentés nevét
        dir_latest_local=$(tail -n+1 $LOCAL_BACKUP_PATH/idorend$1 | head -n1) 
        #  Feltétel, mely először a szinkronizált fájlok számát vizsgálja, majd a két könyvtár közötti különbséget
        if [[ $transferred_files = 0 && ! $(diff -r $dir_latest_local ${LOCAL_BACKUP_PATH}/$BACKUP_DIR) ]]; then
            echo -e "${BLUE}\nNincs szükség új mentésre a $1 mappában.${NC}"
        else
            case $1 in
                "daily")
                    copy_backup $1
                    remove_oldies $DAYS_TO_STAY daily
                ;;
                "weekly")
                    # A ${#VALTOZO} kifejezés megadja a változó karakterhosszát, azért így, mert változó lehet az db név hossza, amivel a fájl kezdődik
                    year_latest=${dir_latest_local:${#dir_latest_local}-13:4}
                    month_latest=${dir_latest_local:${#dir_latest_local}-9:2}
                    day_latest=${dir_latest_local:${#dir_latest_local}-7:2}
                    week_latest=$(date --date="$year_latest-$month_latest-$day_latest" +"%V")
                    if [[ $(date +'%V') != $week_latest ]]; then
                        copy_backup $1
                        remove_oldies $WEEKS_TO_STAY weekly
                    else
                        echo -e "${BLUE}\nNincs szükség új mentésre a $1 mappában (még nincs következő hét).${NC}"
                    fi
                ;;
                "yearly")
                    year_latest=${dir_latest_local:${#dir_latest_local}-13:4}
                    if [ "$(date +'%Y')" != "$year_latest" ]; then
                        copy_backup $1
                    else
                        echo -e "${BLUE}\nNincs szükség új mentésre a $1 mappában (még nincs következő év).${NC}"
                    fi
                ;;
            esac
        fi
    fi
}

#  Napi, heti, éves mentések ellenőrzése és végrehajtása
check_backup daily
check_backup weekly
check_backup yearly
