#!/bin/bash

echo "Transfer mezi mailboxservery. v.0.1"
echo "RUN AS ZIMBRA USER!"

echo -n "Zadejte účet (email), který chcete přesunout: "; read ACCOUNT1
zimbraMailHost=`zmprov -l ga $ACCOUNT1 | grep zimbraMailHost`
test=${zimbraMailHost:0:14}
if [ "$test" != "zimbraMailHost" ]; then
echo "Účet $ACCOUNT1 neexistuje!"
exit 255;
fi

SERVER1=${zimbraMailHost:16}
echo "Zdrojový server (aktuální umístění): $SERVER1"

echo -n "Zadejte cílový server: "; read SERVER2
if [ $SERVER1 == $SERVER2 ]; then
echo "Zdrojový a cílový server nemůže být stejný!"
exit 255;
fi

echo -n "Zadejte dočasný adresář pro umístění dat: "; read TEMPDIR
if [ ! -d $TEMPDIR ]; then
echo "Adresář $TEMPDIR neexistuje!"
exit 255;
fi

# vytvoreni noveho uctu
echo "Vytvářím dočasný účet na serveru $SERVER2..."
TEMPACCOUNT="temp_$ACCOUNT1"

# doplnění hesla a dalších věcí
echo "Kopíruji nastavení ze starého účtu..."

NAMA_FILE="$TEMPDIR/zcs-acc-add.zmp"
LDIF_FILE="$TEMPDIR/zcs-acc-mod.ldif"

rm -f $NAMA_FILE
rm -f $LDIF_FILE

touch $NAMA_FILE
touch $LDIF_FILE

NAME=`echo $ACCOUNT1`;
DOMAIN=`echo $ACCOUNT1 | awk -F@ '{print $2}'`;
ACCOUNT=`echo $ACCOUNT1 | awk -F@ '{print $1}'`;
ACC=`echo $ACCOUNT1 | cut -d '.' -f1`

ZIMBRA_LDAP_PASSWORD=`zmlocalconfig -s zimbra_ldap_password | cut -d ' ' -f3`
LDAP_MASTER_URL="ldapi:///"

OBJECT="(&(objectClass=zimbraAccount)(mail=$NAME))"
dn=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep dn:`
displayName=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep displayName: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
givenName=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep givenName: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
#userPassword=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep userPassword: | cut -d ':' -f3 | sed 's/^ *//g' | sed 's/ *$//g'`
userPassword=`zmprov -l ga $ACCOUNT1 userPassword | grep userPassword | sed 's/userPassword: //'`
cn=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep cn: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
initials=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep initials: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`
sn=`/opt/zimbra/bin/ldapsearch -H $LDAP_MASTER_URL -w $ZIMBRA_LDAP_PASSWORD -D uid=zimbra,cn=admins,cn=zimbra -x $OBJECT | grep sn: | cut -d ':' -f2 | sed 's/^ *//g' | sed 's/ *$//g'`


if [ $ACC = "admin" ] || [ $ACC = "wiki" ] || [ $ACC = "galsync" ] || [ $ACC = "ham" ] || [ $ACC = "spam" ]; then
    echo "Nelze přesouvat systémové účty!"
    exit 255
else
    echo "createAccount $TEMPACCOUNT XXXccc123wQ displayName '$displayName' givenName '$givenName' sn '$sn' initials '$initials' zimbraPasswordMustChange FALSE zimbraMailHost $SERVER2" >> $NAMA_FILE

    pos2=`expr index "$TEMPACCOUNT" @`
    TEMPUSER=${TEMPACCOUNT:0:pos2-1}
    dn2="${dn/$ACCOUNT/$TEMPUSER}"
    echo "$dn2
changetype: modify
replace: userPassword
userPassword: $userPassword
" >> $LDIF_FILE
    echo "Adding account $NAME"
fi


if [ -f $NAMA_FILE ];
then
    if [ -f $LDIF_FILE ];
        then
            zmprov < $NAMA_FILE
            ldapmodify -f $LDIF_FILE -x -H $LDAP_MASTER_URL -D cn=config -w $ZIMBRA_LDAP_PASSWORD
        else
            echo "Chyba, soubor $LDIF_FILE neexistuje."
            exit 255
        fi
else
    echo "Chyba, soubor $NAMA_FILE neexistuje."
    exit 255
fi

echo "Dočasný účet vytvořen."

echo "Zahajuji přesun dat."

echo "Zálohování ze starého účtu $ACCOUNT1 na serveru $SERVER1"
ZMBOX=/opt/zimbra/bin/zmmailbox
DATE=`date +"%Y%m%d%H%M%S"`
$ZMBOX -z -m $ACCOUNT getRestURL "//?fmt=tgz" > $TEMPDIR/$ACCOUNT1.$DATE.tar.gz

echo "Obnovuji data do dočasného $TEMPACCOUNT účtu na serveru $SERVER2"
$ZMBOX -z -m $TEMPACCOUNT postRestURL "//?fmt=tgz&resolve=reset" $TEMPDIR/$ACCOUNT1.$DATE.tar.gz

echo "Přejmenování starého účtu na old_$ACCOUNT1..."
# prejmenovani stareho
zmprov renameAccount $ACCOUNT1 old_$ACCOUNT1

echo "Uzavření starého účtu old_$ACCOUNT1..."
zmprov ma old_$ACCOUNT1  zimbraAccountStatus closed

echo "Přejmenování dočasného účtu na $ACCOUNT1..."
# prejmenovani noveho
zmprov renameAccount $TEMPACCOUNT $ACCOUNT1

echo "HOTOVO."
exit

