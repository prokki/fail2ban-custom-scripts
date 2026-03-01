#!/bin/sh

################################################################################
#
# runtime variables
#
# !!! adapt for your needs !!!
#
################################################################################

# template with already collected bad user agents
BADBOT_ONLINE_LISTFILE=https://github.com/mitchellkrogza/apache-ultimate-bad-bot-blocker/raw/ab496b45bbc5c9ecabc2fc678441c672cdb0271a/_generator_lists/bad-user-agents-htaccess.list

# custom/own bad user agents
# each user agents per line, no escaped characters
BADBOT_LOCAL_LISTFILE=

# fail2ban filter file to replace the badbots line with
BADBOT_FAIL2BAN_FILTERFILE=/etc/fail2ban/filter.d/apache-badbots.local

# create a backup? 1=YES, 0=NO
BADBOT_FAIL2BAN_FILTERFILE_BACKUP=1

# regex to to replace the badbots line with could be "badbotscustom\s*=\s*"
# or "badbots\s*=\s*" for your apache-badbots.conf/.local file.
BADBOT_FAIL2BAN_BADBBOT_REGEX="badbotscustom\s*=\s*"

################################################################################
#
# check dependencies
#
################################################################################

if ! command -v sudo >/dev/null 2>&1; then
  echo "Error: 'sudo' command is required but not installed. Please install package 'sudo'." >&2
  exit 1
fi

if ! command -v wget >/dev/null 2>&1; then
  echo "Error: 'wget' command is required but not installed. Please install package 'wget'." >&2
  exit 1
fi

################################################################################
#
# do not run as user root
#
################################################################################

if [ "$(id -u)" -eq 0 ]; then
    echo "Please do not run this script as root/sudo. It will ask for password when needed."
    exit 1
fi

################################################################################
#
# download & clean template file
#
################################################################################

echo -n "1. Getting bad bots from "
echo "$(printf "%.60s..." "$BADBOT_ONLINE_LISTFILE")"

# create random file
BADBOT_TEMPFILE=$(mktemp /tmp/apache_bad_bot_listfile.XXXXXX)

# download list file
wget -q -O "$BADBOT_TEMPFILE" $BADBOT_ONLINE_LISTFILE

# in the current file all whitespaces are escaped with backslash
# -> replace escaped whitespaces with normal whitespace
sed --in-place 's/\\ / /g' "$BADBOT_TEMPFILE"

echo "  Found $(cat "$BADBOT_TEMPFILE" | wc -l) bad bots."

################################################################################
#
# add local/custom bots
#
################################################################################

echo -n "2. Adding local bad bots from "
echo "$(printf "%.60s..." "$BADBOT_LOCAL_LISTFILE")"

# add bots only, if variable is set
if [ -n "$BADBOT_LOCAL_LISTFILE" ]; then
  # check if file exists
  if [ ! -f "$BADBOT_LOCAL_LISTFILE" ]; then
    echo "Local bad bot list file $BADBOT_LOCAL_LISTFILE not found" >&2
    exit 1
  fi
  # combine both files
  #echo "sort --ignore-case --numeric-sort --output=\"$BADBOT_TEMPFILE\" \"$BADBOT_TEMPFILE\" \"$BADBOT_LOCAL_LISTFILE\""
  echo "  Found $(cat "$BADBOT_LOCAL_LISTFILE" | wc -l) more bad bots."
  sort --ignore-case --numeric-sort --output="$BADBOT_TEMPFILE" "$BADBOT_TEMPFILE" "$BADBOT_LOCAL_LISTFILE"
else
  echo "  No local loist file specified."
fi

################################################################################
#
# prepare entrieslist items to use in fail2ban file
#
################################################################################

echo "3. Merging and preparing bad bot names..."

# remove duplicates
BADBOT_TEMPFILE_SORTED=$BADBOT_TEMPFILE.sorted
uniq "$BADBOT_TEMPFILE" > "$BADBOT_TEMPFILE_SORTED"
echo "  Duplicate bot names removed."

# escape special charaters to use the output in regular expressions
# in fail2ban expressions like badbotscustom=...
#echo "sed -i 's/[.^$*\\()/[]/\\&/g' \"$BADBOT_TEMPFILE_SORTED\""
sed -i 's/[.^$*\\()/[]/\\&/g' "$BADBOT_TEMPFILE_SORTED"

# convert lines to single line with | 
#echo "paste -sd '|' \"$BADBOT_TEMPFILE_SORTED\""
BADBOT_ONE_LINE=$(paste -sd '|' "$BADBOT_TEMPFILE_SORTED")
#echo "$BADBOT_ONE_LINE"
echo "  Converted lines to single line."

################################################################################
#
# write badbots to fail2ban file
#
################################################################################

echo "4. Adapting fail2ban filter file..."

if [ "$BADBOT_FAIL2BAN_FILTERFILE_BACKUP" -eq 1 ]; then
  sudo cp "$BADBOT_FAIL2BAN_FILTERFILE" "$BADBOT_FAIL2BAN_FILTERFILE.bak"
  echo "  Created backup file $BADBOT_FAIL2BAN_FILTERFILE.bak"
fi


# again escape all regular expression special chars
# first escaping is neccessary to use the user agents (keep special chars) in fail2ban regex
# this escaping is neccessary to use the user agents (keep special chars) in upcoming sed statement
ESCAPED_BADBOT_ONE_LINE=$(echo "$BADBOT_ONE_LINE" | sed 's/[.^$*\\()/[]/\\&/g')
#echo "$ESCAPED_BADBOT_ONE_LINE"

# replace in fail2ban filter file
#echo "sed --in-place --regexp-extended 's/^(badbotscustom\s*=\s*).*$/\1$BADBOT_ONE_LINE/' \"$BADBOT_FAIL2BAN_FILTERFILE\""
sudo sed --in-place --regexp-extended 's/^(badbotscustom\s*=\s*).*$/\1'"$ESCAPED_BADBOT_ONE_LINE"'/' "$BADBOT_FAIL2BAN_FILTERFILE"
echo "  Adapated file $BADBOT_FAIL2BAN_FILTERFILE"

exit 0
