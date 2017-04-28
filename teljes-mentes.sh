#!/bin/bash

#  Fájlnév: teljes-mentes.sh
#  Leírás: Ssh-n keresztül MYSQL adatbázis teljes mentését elvégző script, daily, weekly, yearly mappákba.
#  Szerző: Dezső János

#  Szerver és azon levő adatbázis címének, felhasználó nevének és a szerveren lévő ideiglenes elérési út megadása
readonly SERVER_LOGIN="user@domain.nev"
readonly SERVER_PORT="23"
readonly SERVER_TEMP_PATH="/home/user/sqltmp/"
readonly DB_USER="root"
readonly DB_NAME="mysql"
readonly DB_PASS="MySqlP4ssWord"

#  Helyi idiglenes elérési út
readonly LOCAL_TEMP_PATH="/tmp"

#  A maximálisan tárolni kívánt napok és hetek száma
readonly DAYS_TO_STAY=7
readonly WEEKS_TO_STAY=8

#  Az aktuális elérési út tárolása
readonly LOCAL_BACKUP_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

#  Mai dátum és idő eltárolása
readonly DATE_TODAY="$(date +'%Y%m%d_%H%M')"

#  echo paranccsal használt színek megadása
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[1;34m'
readonly NC='\033[0m' # No Color

#  Új mentés készítése a szerveren az adatbázisról, majd annak méretének változóba mentése
ssh $SERVER_LOGIN -p $SERVER_PORT "mkdir -p $SERVER_TEMP_PATH"
ssh $SERVER_LOGIN -p $SERVER_PORT "mysqldump -u$DB_USER -p$DB_PASS $DB_NAME > ${SERVER_TEMP_PATH}${DB_NAME}_backup_$DATE_TODAY.sql"
new_backup_size=$(ssh $SERVER_LOGIN -p $SERVER_PORT "stat -c %s ${SERVER_TEMP_PATH}${DB_NAME}_backup_$DATE_TODAY.sql")
new_backup_md5=$(ssh $SERVER_LOGIN -p $SERVER_PORT "head -n -1 ${SERVER_TEMP_PATH}${DB_NAME}_backup_$DATE_TODAY.sql | md5sum" | awk '{ print $1 }')

#  Elérési utak biztosítása a mentések számára
mkdir -p "$LOCAL_BACKUP_PATH/daily"
mkdir -p "$LOCAL_BACKUP_PATH/weekly"
mkdir -p "$LOCAL_BACKUP_PATH/yearly"

#  Függvény, mely kiírja a képernyőre a friss mentés méretét és md5 hash értékét
function get_new_backup_data {
    echo -e "A friss mentés (${DB_NAME}_backup_$DATE_TODAY.sql) mérete: ${BLUE}$new_backup_size ${NC}byte,"
    echo -e "md5 hash értéke: ${BLUE}$new_backup_md5 ${NC}"
}

#  Függvény, mely visszaadja az paraméterként megadott file méretét
function get_file_size {
    echo "$(stat -c %s $1 2>/dev/null )"
}

#  Függvény, mely visszaadja az paraméterként megadott file md5 hash értékét
function get_file_md5 {
    echo "$(head -n -1 $1 | md5sum | awk '{ print $1 }')"
}

#  Függvény, mely kiírja a képernyőre a legutolsó mentés méretét és md5 hash értékét
function get_old_backup_data {
    echo -e "\nAz utolsó helyi $1 mentés ($file_latest_local) mérete: ${BLUE}$(get_file_size $file_latest_local) ${NC}byte,"
    echo -e "md5 hash értéke: ${BLUE}$(get_file_md5 $file_latest_local) ${NC}"
}

#  Függvény, amely letölti a backupot az ideiglenes mappába
function download_backup {
    #  Képernyőre írjuk az új mentés adatait
    get_new_backup_data
    echo -e "${BLUE}Új backup mentése a $1 mappába${NC}"
    if [ ! "$(ls ${LOCAL_TEMP_PATH}/${DB_NAME}_backup_$DATE_TODAY.sql 2> /dev/null)" ]; then 
        #  Ha az rsync parancs hibával áll le, akkor a script futtatása megállítva
        set -e
        #  Szinkronizálás a helyi ideiglenes könyvtárba
        rsync -HavXx -e "ssh -p $SERVER_PORT" $SERVER_LOGIN:${SERVER_TEMP_PATH}${DB_NAME}_backup_$DATE_TODAY.sql ${LOCAL_TEMP_PATH} --info=progress2
    fi
    #  Az ideiglenes könyvtárból az aktuálisba másolás
    cp ${LOCAL_TEMP_PATH}/${DB_NAME}_backup_$DATE_TODAY.sql ./
    echo -e "${GREEN}Új backup mentve a $1 mappába.${NC}"
}

#  Függvény, mely törli $1 változóban definiált értéket meghaladó mentést
function remove_oldies {
        number_of_rows=$(wc -l < idorend)
        if [[ $number_of_rows -gt $1-1 ]]; then
            toremove=$(tail -n+7 idorend | head -n1)
            rm $toremove
            echo -e "${RED}Régi mentés törölve a daily mappából: $toremove${NC}"
        fi
}

#  Függvény, mely eldönti, hogy szükséges-e menteni, és amennyiben igen, végrehajtja a $1 értéken kapott könyvtárra
function check_backup {
    cd "$LOCAL_BACKUP_PATH/$1"
    #  Fetétel, mely vizsgálja, hogy létezik-e már mentés
    if [ ! "$(ls $LOCAL_BACKUP_PATH/$1/${DB_NAME}_backup_* 2> /dev/null)" ]; then
        echo -e "${BLUE}\nElső mentés a $1 mappába:${NC}"
        download_backup $1
    else
        #  Az "idorend" fájlba létrehoz egy listát csökkenő időrendbe a mentések fájlneveiből
        ls ${DB_NAME}_backup_* -1 | sort -r > idorend
        #  Eltárolja a legutolsó meglévő mentés nevét
        file_latest_local=$(tail -n+1 idorend | head -n1)       
        #  Feltétel, mely először fájlméret alapján vizsgál, majd ha az egyezik, md5 hash alapján hasonlítja össze a legutolsó és a legújabb mentést
        if [[ "$new_backup_size" == "$(get_file_size $file_latest_local)" && "$new_backup_md5" == "$(get_file_md5 $file_latest_local)" ]]; then
            echo -e "${BLUE}\nNincs szükség új mentésre a $1 mappában (azonos md5 hash).${NC}"
        else
            case $1 in
                "daily")
                    #  Ha új mentés készül, akkor képernyőre írjuk a legutolsó mentés adatait
                    get_old_backup_data $1
                    download_backup $1
                    remove_oldies $DAYS_TO_STAY
                ;;
                "weekly")
                    # A ${#VALTOZO} kifejezés megadja a változó karakterhosszát, azért így, mert változó hosszúságú lehet az adatbázis név hossza, amivel a fájl kezdődik
                    year_latest=${file_latest_local:${#file_latest_local}-17:4}
                    month_latest=${file_latest_local:${#file_latest_local}-13:2}
                    day_latest=${file_latest_local:${#file_latest_local}-11:2}
                    week_latest=$(date --date="$year_latest-$month_latest-$day_latest" +"%V")
                    if [[ $(date +'%V') != $week_latest ]]; then
                        get_old_backup_data $1
                        download_backup $1
                        remove_oldies $WEEKS_TO_STAY
                    else
                        echo -e "${BLUE}\nNincs szükség új mentésre a $1 mappában (még nincs következő hét).${NC}"
                    fi
                ;;
                "yearly")
                    year_latest=${file_latest_local:${#file_latest_local}-17:4}
                    if [ "$(date +'%Y')" != "$year_latest" ]; then
                        get_old_backup_data $1
                        download_backup $1
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

#  A helyi idiglenes mentés törlése a lemezről (hibaüzenet figyelmenkívülhagyásával, ha nem készült mentés)
rm ${LOCAL_TEMP_PATH}/${DB_NAME}_backup_$DATE_TODAY.sql 2> /dev/null
#  A szerveren lévő idiglemes fájl törlése
ssh $SERVER_LOGIN -p $SERVER_PORT "rm ${SERVER_TEMP_PATH}${DB_NAME}_backup_$DATE_TODAY.sql"
