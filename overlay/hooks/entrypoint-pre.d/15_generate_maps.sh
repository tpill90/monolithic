#!/bin/bash

# Maps the various domains per CDN to a single identifier, such as [epic] [blizzard] [steam].  This allows for a better cache hit rate
# as there will only be one total copy of the data versus one copy per domain.

echo "  Bootstrapping Monolithic from ${CACHE_DOMAINS_REPO}"

cd /data/cachedomains

if [[ "${NOFETCH:-false}" != "true" ]]; then
    echo "  Pulling latest from cache-domains repo"
    # Disable error checking whilst we attempt to get latest
	set +e
	git remote set-url origin ${CACHE_DOMAINS_REPO}
	git fetch origin || echo "Failed to update from remote, using local copy of cache_domains"
	git reset --hard origin/${CACHE_DOMAINS_BRANCH}
	# Reenable error checking
	set -e
fi

TEMP_PATH=$(mktemp -d)
OUTPUTFILE=${TEMP_PATH}/outfile.conf
echo "map \"\$http_user_agent£££\$http_host\" \$cacheidentifier {" >> $OUTPUTFILE
echo "    default \$http_host;" >> $OUTPUTFILE
echo "    ~Valve\\/Steam\\ HTTP\\ Client\\ 1\.0£££.* steam;" >> $OUTPUTFILE

jq -r '.cache_domains | to_entries[] | .key' cache_domains.json | while read CACHE_ENTRY; do

    echo ""
	#for each cache entry, find the cache identifier
	CACHE_IDENTIFIER=$(jq -r ".cache_domains[$CACHE_ENTRY].name" cache_domains.json)
	jq -r ".cache_domains[$CACHE_ENTRY].domain_files | to_entries[] | .key" cache_domains.json | while read CACHEHOSTS_FILEID; do

		#Get the key for each domain files
		jq -r ".cache_domains[$CACHE_ENTRY].domain_files[$CACHEHOSTS_FILEID]" cache_domains.json | while read CACHEHOSTS_FILENAME; do

			#Get the actual file name
			echo "  Reading domains from ${CACHEHOSTS_FILENAME}"

            # for each file in the hosts file
			cat ${CACHEHOSTS_FILENAME} | while read CACHE_HOST; do
                # remove all whitespace (mangles comments but ensures valid config files)
				CACHE_HOST=${CACHE_HOST// /}

                # Skipping empty lines
                if [ "x${CACHE_HOST}" == "x" ]; then
                    continue
                fi

                # Skipping comments
                if [[ $CACHE_HOST == \#* ]]; then
                    continue
                fi

                echo "    new host: $CACHE_HOST"

                #Use sed to replace . with \. and * with .*
                REGEX_CACHE_HOST=$(sed -e "s#\.#\\\.#g" -e "s#\*#\.\*#g" <<< ${CACHE_HOST})
                echo "    ~.*£££.*?${REGEX_CACHE_HOST} ${CACHE_IDENTIFIER};" >> $OUTPUTFILE

			done
		done
	done
done
echo "}" >> $OUTPUTFILE

echo ""
echo "Resulting 30_maps.conf file:"
cat $OUTPUTFILE

cp $OUTPUTFILE /etc/nginx/conf.d/30_maps.conf
rm -rf $TEMP_PATH
