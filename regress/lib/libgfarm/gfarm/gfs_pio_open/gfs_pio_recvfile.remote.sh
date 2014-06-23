#!/bin/sh

. ./regress.conf

# client runs on a (possibly) non-filesystem node

host=`hostname`

if host=`gfsched -D $host 2>/dev/null`; then
	host=`gfsched | awk '$0 != "'$host'" { print $0; exit }'`
else
	host=`gfsched | head -1`
fi
if [ -z "$host" ]; then
	exit $exit_unsupported
fi
$testbase/gfs_pio_recvfile.sh -h $host