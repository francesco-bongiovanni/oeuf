echo "sending notifications about broken build"

#Send us email
echo $1

md5sum $1

env


cat $1 | mail -s "[OEUF BUILD BOT] Build is Broken" emullen

cat $1 | mail -s "[OEUF BUILD BOT] Build is Broken" emullen@cs.washington.edu
# cat $1 | mail -s "[OEUF BUILD BOT] Build is Broken" jrw12@cs.washington.edu
# cat $1 | mail -s "[OEUF BUILD BOT] Build is Broken" spernste@cs.washington.edu



#Post in slack
#credit to Calvin for this
curl -sf -XPOST \
     --data-urlencode "payload={\"channel\":\"#oeuf\",\"link_names\":1,\"text\":\"$(python -c 'import sys; print(sys.argv[1].replace("\"", "\\\""))' "Build Broken")\"}" \
     'https://hooks.slack.com/services/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'


