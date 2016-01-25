#!/bin/sh

# Start searchd without detach into background
# @author   leodido   <leodidonato@gmail.com>
exec searchd --nodetach "$@"
