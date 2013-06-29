#!/bin/sh
### BEGIN INIT INFO
# Provides:          unicorn
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Manage unicorn server
# Description:       Start, stop, restart unicorn server for a specific application.
### END INIT INFO
set -e

# Feel free to change any of the following variables for your app:
TIMEOUT=${TIMEOUT-60}
APP_ROOT=/home/deployer/apps/toolbox/current
PID=$APP_ROOT/tmp/pids/unicorn.pid
CMD="cd $APP_ROOT; bundle exec unicorn -D -c $APP_ROOT/config/unicorn.rb -E production"
AS_USER=deployer
set -u

OLD_PIN="$PID.oldbin"

sig () {
  test -s "$PID" && kill -$1 `cat $PID`
}

oldsig () {
  test -s $OLD_PIN && kill -$1 `cat $OLD_PIN`
}

run () {
  if [ "$(id -un)" = "$AS_USER" ]; then
    eval $1
  else
    su -c "$1" - $AS_USER
  fi
}

case "$1" in
start)
  sig 0 && echo >&2 "Already running" && exit 0
  run "$CMD"
  ;;
stop)
  sig QUIT && exit 0
  echo >&2 "Not running"
  ;;
force-stop)
  sig TERM && exit 0
  echo >&2 "Not running"
  ;;
restart|reload)
  sig HUP && echo reloaded OK && exit 0
  echo >&2 "Couldn't reload, starting '$CMD' instead"
  run "$CMD"
  ;;
upgrade)
  if sig USR2 && sleep 2 && sig 0 && oldsig QUIT
  then
    n=$TIMEOUT
    while test -s $OLD_PIN && test $n -ge 0
    do
      printf '.' && sleep 1 && n=$(( $n - 1 ))
    done
    echo

    if test $n -lt 0 && test -s $OLD_PIN
    then
      echo >&2 "$OLD_PIN still exists after $TIMEOUT seconds"
      exit 1
    fi
    exit 0
  fi
  echo >&2 "Couldn't upgrade, starting '$CMD' instead"
  run "$CMD"
  ;;
reopen-logs)
  sig USR1
  ;;
*)
  echo >&2 "Usage: $0 <start|stop|restart|upgrade|force-stop|reopen-logs>"
  exit 1
  ;;
esac

setup () {
    CONFIG=$1
 
    if [ -z $APP_NAME ]; then
        echo "App name is not defined in ${CONFIG}"
        return 1
    fi
    if [ -z $APP_USER ]; then
        echo "App name is not defined in ${CONFIG}"
        return 1
    fi
    if [ -z $RAILS_ROOT ]; then
        echo "Rails root is not defined in ${CONFIG}"
        return 1
    fi
    if [ -z $RAILS_ENV ]; then
        echo "Rails environment is not defined in ${CONFIG}"
        return 1
    fi
    # If unicorn binary was not defined in config
    if [ -z $UNICORN ]; then
      UNICORN="${RAILS_ROOT}/bin/unicorn"
    fi
 
    echo "Launching ${APP_NAME} (${RAILS_ROOT})"
 
    cd $RAILS_ROOT || return 1
    export PID=$RAILS_ROOT/tmp/pids/unicorn.pid
 
    # SUDOCMD="rvmsudo -u ${APP_USER}"
    SUDOCMD="sudo -u ${APP_USER}"
 
    CMD="${SUDOCMD} RAILS_ENV=${RAILS_ENV} ${UNICORN} -E ${RAILS_ENV} -c ${RAILS_ROOT}/config/unicorn.rb -D"
    return 0
}

# either run the start/stop/reload/etc command for every config under /etc/unicorn
# or just do it for a specific one
 
# $1 contains the start/stop/etc command
# $2 if it exists, should be the specific config we want to act on
 
if [ $2 ]; then
  . /etc/unicorn/$2.conf
  setup "/etc/unicorn/$2.conf"
  if [ $? -eq 1 ]; then
    exit
  fi
  cmd $1
else
  for CONFIG in /etc/unicorn/*.conf; do
    # clean variables from prev configs
    unset APP_NAME
    unset APP_USER
    unset RAILS_ROOT
    unset RAILS_ENV
    unset UNICORN
 
    # import the variables
    . $CONFIG
    setup $CONFIG
    if [ $? -eq 1 ]; then
      continue
    fi
    # run the start/stop/etc command
    cmd $1
  done
fi