#!/bin/sh

. ./regress.conf

if $testbin/gfxattr -g -n gfarm.ncopy /.not/.exist /.not/.exist
then
  :
else
  exit_code=$exit_pass
fi
exit $exit_code
