#!/bin/sh

set -e

export LC_ALL=C

if ! test -t 2; then
    cat 1>&2 <<EOF
This script must be run interactively, and its standard error output must not
be redirected.
EOF
    exit 2
fi

for utility in dd grep tr hexdump basename cut sed; do
    if ! which $utility >/dev/null 2>&1 || ! test -x $(which $utility 2>/dev/null); then
        echo "The $utility utility is required." >&2
        exit 6
    fi
done

if which sha256sum >/dev/null 2>&1; then
    HASH_METHOD=sha256sum
elif which openssl >/dev/null 2>&1; then
    HASH_METHOD=openssl
else
    echo "Either the sha256sum utility or the openssl utility are required.">&2
    exit 6
fi

if test -d /dev/fd; then
    DELIVERY_METHOD=/dev/fd
elif which mktemp >/dev/null 2>&1; then
    DELIVERY_METHOD=mktemp
else
    echo "Either your OS must have /dev/fd, or you must have mktemp." >&2
    exit 6
fi

SALMON_PATH=$(echo "$0" | sed -e 's/\.sh$//').lua

if ! echo "$SALMON_PATH" | grep -q '/'; then
    if which "$SALMON_PATH" >/dev/null 2>&1; then
        SALMON_PATH=$(which "$SALMON_PATH" 2>/dev/null)
    fi
fi

if ! [ -f "$SALMON_PATH" ]; then
    cat >&2 <<EOF
I couldn't find Salmon. It should be in the same place as this script, but with
a .lua extension.
EOF
    exit 7
elif ! [ -x "$SALMON_PATH" ]; then
    cat <<EOF
Salmon is not executable.
EOF
    exit 8
fi

if [ -t 0 -a -t 1 ]; then
    cat 1>&2 <<EOF
One or both of standard input or standard output must be redirected.

Example usages:

salmon.sh > encrypted_text
salmon.sh < encrypted_text | less
tar -c --lzip -f - secret_folder/ | salmon.sh > encrypted.tar.lzip

You may optionally supply a nonce as the only command line argument, as in:
tar -c --lzip -f - secret_folder/ | salmon.sh 0123456789ABCDEF0123456789ABCDEF > encrypted-0123456789ABCDEF0123456789ABCDEF.tar.lzip
EOF
    exit 3
fi

NONCE=""
if ! [ x"$1" = x ]; then
    NONCE="$1"
    if [ $(echo "$NONCE" | wc -c) -ne 33 ] \
           || (echo "$NONCE" | grep -q '[^0-9A-Fa-f]'); then
        cat 1>&2 <<EOF
The nonce you provided was invalid. A nonce must consist of exactly 32
hexadecimal digits.
EOF
        exit 4
    fi
else
    cat 1>&2 <<EOF
Are you decrypting? If so, paste the nonce here and press enter. If not, just
press enter.
EOF
fi
while [ x"$NONCE" = x ]; do
    NONCE=$(head -n 1 <&2)
    if [ x"$NONCE" = x ]; then
        NONCE=$(dd if=/dev/random bs=16 count=1 status=none | hexdump -e '/1 "%02x"')
        if [ $(echo "$NONCE" | wc -c) -ne 33 ] \
               || (echo "$NONCE" | grep -q '[^0-9A-Fa-f]'); then
            cat 1>&2 <<EOF
We weren't able to generate a nonce. (Is /dev/random available?) Aborting.
EOF
            exit 4
        fi
        cat >&2 <<EOF
Generated a nonce: $NONCE
(Save this, as you will need it to decrypt this later.)
EOF
    elif [ $(echo "$NONCE" | wc -c) -ne 33 ] \
             || (echo "$NONCE" | grep -q '[^0-9A-Fa-f]'); then
        cat 1>&2 <<EOF
That nonce is invalid. Try again.
(A nonce must consist of exactly 32 hexadecimal digits.)
EOF
        NONCE=""
    fi
done

if which stty >/dev/null 2>&1; then
    HAVE_STTY=1
else
    HAVE_STTY=0
fi

KEY=""
PASSPHRASE=""
PASSPHRASE2=""
while [ x"$KEY" = x ]; do
    if [ $HAVE_STTY -ne 0 ]; then
        stty -echo >&2 <&2
    fi
    printf "Enter passphrase: " >&2
    set +e
    PASSPHRASE=$(head -n 1 <&2)
    if [ $? -ne 0 ] || [ x"$PASSPHRASE" = x ]; then
        if [ $HAVE_STTY -ne 0 ]; then
            echo >&2
        fi
        stty echo >&2 <&2
        echo "Aborting." >&2
        exit 5
    fi
    if [ $HAVE_STTY -ne 0 ]; then
        echo >&2
    fi
    printf "Confirm passphrase: " >&2
    PASSPHRASE2=$(head -n 1 <&2)
    if [ $? -ne 0 ]; then
        if [ $HAVE_STTY -ne 0 ]; then
            echo >&2
        fi
        stty echo >&2 <&2
        echo "Aborting." >&2
        exit 5
    fi
    set -e
    if [ $HAVE_STTY -ne 0 ]; then
        stty echo >&2 <&2
        echo >&2
    fi
    if ! [ x"$PASSPHRASE" = x"$PASSPHRASE2" ]; then
        echo "The passphrases don't match. Try again." >&2
    else
        case "$HASH_METHOD" in
            sha256sum)
                KEY=$(echo "$PASSPHRASE" | tr -d '\n' | sha256sum \
                             | cut -b 1-64)
            ;;
            openssl)
                KEY=$(echo "$PASSPHRASE" | tr -d '\n' | openssl sha256 \
                             | cut -b 9-72)
            ;;
            *)
                echo "Unimplemented HASH_METHOD, this should never happen." >&2
                exit 9
                ;;
        esac
    fi
    PASSPHRASE=""
    PASSPHRASE2=""
done

case "$DELIVERY_METHOD" in
    /dev/fd)
        "$SALMON_PATH" /dev/fd/3 3<<EOF
$KEY$NONCE
EOF
        ;;
    mktemp)
        TEMPFILE=`mktemp`
        cat > "$TEMPFILE" <<EOF
$KEY$NONCE
EOF
        # hopefully give it enough time to open $TEMPFILE before we delete it
        (sleep 0.25; rm "$TEMPFILE") &
        "$SALMON_PATH" "$TEMPFILE"
        ;;
    *)
        echo "Unimplemented DELIVERY_METHOD, this should never happen." >&2
        exit 9
        ;;
esac
KEY=""
NONCE=""

