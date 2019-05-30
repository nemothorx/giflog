#!/bin/bash

#rewrite of original giflog. takes up to three parameters. 

# $1 - a URL to an image (or function)
#	functions for complrex pre-recorded stuff. in a lib/giflog.d/  ?
# $2 - optionally: a local name to save the image to
# $3 - optionally: commandline options to give to imagemagick directly

# images are saved with their metadata intact from http headers. filename includes datestamp of retrieval time, thus guaranteeing uniqueness

# however, images are md5sum'd against the previous save, and discarded if
# identical

# TODO
# we should make some .index htmls (for i.php) too?
# should we use FTP to source data?
#   ftp://ftp.bom.gov.au/anon/gen/gms/

LOGFILE=$HOME/var/log/giflog.log
LIBDIR=$HOME/lib/giflog/
INVBASEDIR=/data/pub   # invisible basedir. This is what we strip from realpath'd files to make the result URL friendly
BASEDIR=$INVBASEDIR/giflog
LASTDIR=$BASEDIR/last
YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
TIME=$(date +%T)


################################# functions ###
do_log() {
	# very simple logging function
	message=$1
	echo "$(date +%FT%T) $reqtag $message" >> $LOGFILE
}

do_diff () {
	# check for similarity and either discard, or keep and symlink
	diff -q "$tfile" "$LASTDIR/$rname" >/dev/null 2>&1
	diffexit=$?
	# diffexit = 0 for identical. 1 for differ. 2 for one or both files nonexistant
	case "$diffexit" in
		0)
		# identical means throw it away. Booooooring
			do_log "=(old)"
			rm $tfile
			;;
		1|2)
		# differs, or missing - assume only missing file should be the 'last' one
			do_log "+(new) $tfile"
			if [ -n "$metadata" ] ; then
				modtime=$(echo "$metadata" | grep "^Last-Modified: ")
				touch -d "${modtime:15:100}" "$tfile"
			fi
			ln -sf "../$CHRONODIR/$tname" "$LASTDIR/$rname"
			source $LIBDIR/mkhtml
			mkhtml # detects $rname and does the right thing
			;;
		*)
		# WTF?
			do_log "!(wtf) diff exited with $diffexit"
			;;
	esac
}

req=$1
reqmd5=$(echo "$req" | md5sum)
reqtag=${reqmd5:0:6}
reqmd5digits=$(echo "$reqmd5" | tr -d -c '[1-9]')
startdelay=$(( ${reqmd5digits:0:6}%54 ))
CHRONODIR=$YEAR/$MONTH/$DAY

TDIR="$BASEDIR/$CHRONODIR"
mkdir -p "$TDIR"

case $req in
	http://*|https://*)
		[ -t 0 ] || sleep $startdelay
		[ -n "$2" ] && rname=$2 || rname=${req##*/}
		imopts=$3
		;;
	*)
		if [ -f "$LIBDIR/$req" ] ; then
			do_log "*(fct) $req"
			source "$LIBDIR/$req" 
			$req "$2" "$3"
		else
			do_log "!(bad) library request fail for $req"
		fi
		exit
		;;
esac
tname="${YEAR}-${MONTH}-${DAY}T${TIME}_$rname"
tfile="${TDIR}/$tname"

do_log "?(get) $req"
metadata=$(curl -s -D - $req -o $tfile)
# TODO: check for a 404 (or any non-200) error and flag it) 4xx erros should resulty in deletion
reqcode=$(echo "$metadata" | head -1 | cut -d' ' -f2)
reqcode2=$(echo "$metadata" | head -1 | cut -d' ' -f3-)
case $reqcode in
	1*)
		do_log ":($reqcode) $reqcode2"
		cont=yes
		;;
	2*)
		do_log ":($reqcode) $reqcode2"
		cont=yes
		;;
	3*)
		do_log ":($reqcode) $reqcode2"
		cont=yes
		;;
	4*)
		do_log ":($reqcode) $reqcode2"
		rm "$tfile"
		cont=no
		;;
esac

# continue?
[ "$cont" != "yes" ] && exit 1

[ ! -s $tfile ] && do_log ":(siz) file zero size" && exit 1


do_log "|(cvt) $imopts"
case $imopts in
    b64)
	# base64 shenanigans found
	# need to pull the base64 data from $tfile
	mv $tfile $TDIR/_tmp_$rname
	cat $TDIR/_tmp_$rname | grep -m 1 -i -o "src=\"data:image.*" | sed -e 's/.*,\(.*\)">/\1/g' | /usr/bin/base64 -d > $tfile
	rm $TDIR/_tmp_$rname
	;;
    *)
#	echo "convert $tfile $imopts $TDIR/_tmp_$rname && mv $TDIR/_tmp_$rname $tfile"
	convert $tfile $imopts $TDIR/_tmp_$rname && mv $TDIR/_tmp_$rname $tfile
	;;
esac

# do_diff runs through the final checks to see if we're different to last time :)
do_diff
