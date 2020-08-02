#!/usr/bin/env bash
set -Eeuo pipefail

# https://www.php.net/gpg-keys.php
declare -A gpgKeys=(
	# https://wiki.php.net/todo/php80
	# pollita & carusogabriel
	# https://www.php.net/gpg-keys.php#gpg-8.0
	[8.0]='1729F83938DA44E27BA0F4D3DBDB397470D12172 BFDDD28642824F8118EF77909B67A5C12229118F'

	# https://wiki.php.net/todo/php74
	# petk & derick
	# https://www.php.net/gpg-keys.php#gpg-7.4
	[7.4]='42670A7FE4D0441C8E4632349E4FDC074A4EF02D 5A52880781F755608BF815FC910DEB46F53EA312'

	# https://wiki.php.net/todo/php73
	# cmb & stas
	# https://www.php.net/gpg-keys.php#gpg-7.3
	[7.3]='CBAF69F173A0FEA4B537F470D66C9593118BCCB6 F38252826ACD957EF380D39F2F7956BC5DA04B5D'

	# https://wiki.php.net/todo/php72
	# pollita & remi
	# https://www.php.net/downloads.php#gpg-7.2
	# https://www.php.net/gpg-keys.php#gpg-7.2
	[7.2]='1729F83938DA44E27BA0F4D3DBDB397470D12172 B1B44D8F021E4E2D6021E995DC9FF8D3EE5AF27F'

	# https://wiki.php.net/todo/php71
	# davey & krakjoe
	# https://secure.php.net/downloads.php#gpg-7.1
	# https://secure.php.net/gpg-keys.php#gpg-7.1
	[7.1]='A917B1ECDA84AEC2B568FED6F50ABC807BD5DCD0 528995BFEDFBA7191D46839EF9BA0ADA31CBD89E'

	# https://wiki.php.net/todo/php70
	# ab & tyrael
	# https://secure.php.net/downloads.php#gpg-7.0
	# https://secure.php.net/gpg-keys.php#gpg-7.0
	[7.0]='1A4E8B7277C42E53DBA9C7B9BCAA30EA9C0D5763 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3'

	# https://wiki.php.net/todo/php56
	# jpauli & tyrael
	# https://secure.php.net/downloads.php#gpg-5.6
	# https://secure.php.net/gpg-keys.php#gpg-5.6
	[5.6]='0BD78B5F97500D450838F95DFE857D9A90D90EC1 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3'

	# https://wiki.php.net/todo/php55
	# jpauli & dsp & stas
	# https://www.php.net/gpg-keys.php#gpg-5.5
	[5.5]='0B96609E270F565C13292B24C13C70B87267B52D 0BD78B5F97500D450838F95DFE857D9A90D90EC1 F38252826ACD957EF380D39F2F7956BC5DA04B5D'

	# https://wiki.php.net/todo/php54
	# stas & dsp
	# https://www.php.net/gpg-keys.php#gpg-5.4
	[5.4]='F38252826ACD957EF380D39F2F7956BC5DA04B5D'

)
# see https://www.php.net/downloads.php

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

githubMatrix=
for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"

	distExt='.xz'
	if [[ ${rcVersion//./} -le 54 ]]; then
		distExt='.bz2'
	fi

	# scrape the relevant API based on whether we're looking for pre-releases
	apiUrl="https://www.php.net/releases/index.php?json&max=100&version=${rcVersion%%.*}"
	apiJqExpr='
		(keys[] | select(startswith("'"$rcVersion"'."))) as $version
		| [ $version, (
			.[$version].source[]
			| select(.filename // "" | endswith("'"$distExt"'"))
			|
				"https://www.php.net/distributions/" + .filename,
				"https://www.php.net/distributions/" + .filename + ".asc",
				.sha256 // "",
				.md5 // ""
		) ]
	'
	if [ "$rcVersion" != "$version" ]; then
		apiUrl='https://qa.php.net/api.php?type=qa-releases&format=json'
		apiJqExpr='
			.releases[]
			| select(.version | startswith("'"$rcVersion"'."))
			| [
				.version,
				.files.xz.path // "",
				"",
				.files.xz.sha256 // "",
				.files.xz.md5 // ""
			]
		'
	fi
	IFS=$'\n'
	possibles=( $(
		curl -fsSL "$apiUrl" \
			| jq --raw-output "$apiJqExpr | @sh" \
			| sort -rV
	) )
	unset IFS

	if [ "${#possibles[@]}" -eq 0 ]; then
		echo >&2
		echo >&2 "error: unable to determine available releases of $version"
		echo >&2
		exit 1
	fi

	# format of "possibles" array entries is "VERSION URL.TAR.XZ URL.TAR.XZ.ASC SHA256 MD5" (each value shell quoted)
	#   see the "apiJqExpr" values above for more details
	eval "possi=( ${possibles[0]} )"
	fullVersion="${possi[0]}"
	url="${possi[1]}"
	ascUrl="${possi[2]}"
	sha256="${possi[3]}"
	md5="${possi[4]}"

	# Equivalent to PHP's PHP_VERSION_ID:
	# 5.6.10 => 50610, 7.1.0 => 70100
	versionId="$(printf '%d%02d%02d' $(echo "$fullVersion" | sed -E 's/([0-9])\.([0-9]{1,2})\.([0-9]{1,2}).*/\1 \2 \3/g'))"

	gpgKey="${gpgKeys[$rcVersion]}"
	if [ -z "$gpgKey" ]; then
		echo >&2 "ERROR: missing GPG key fingerprint for $version"
		echo >&2 "  try looking on https://www.php.net/downloads.php#gpg-$version"
		exit 1
	fi

	# if we don't have a .asc URL, let's see if we can figure one out :)
	if [ -z "$ascUrl" ] && wget -q --spider "$url.asc"; then
		ascUrl="$url.asc"
	fi

	dockerfiles=()

	for suite in buster alpine3.12; do
		[ -d "$version/$suite" ] || continue
		alpineVer="${suite#alpine}"

		baseDockerfile=Dockerfile-debian.template
		if [ "${suite#alpine}" != "$suite" ]; then
			baseDockerfile=Dockerfile-alpine.template
		fi

		for variant in cli cli-debug apache fpm zts; do
			[ -d "$version/$suite/$variant" ] || continue

			{ generated_warning; cat "$baseDockerfile"; } > "$version/$suite/$variant/Dockerfile"

			echo "Generating $version/$suite/$variant/Dockerfile from $baseDockerfile + $variant-Dockerfile-block-*"
			gawk -i inplace -v variant="$variant" '
				$1 == "##</autogenerated>##" { ia = 0 }
				!ia { print }
				$1 == "##<autogenerated>##" { ia = 1; ab++; ac = 0; if (system("test -f " variant "-Dockerfile-block-" ab) != 0) { ia = 0 } }
				ia { ac++ }
				ia && ac == 1 { system("cat " variant "-Dockerfile-block-" ab) }
			' "$version/$suite/$variant/Dockerfile"

			cp -a \
				docker-php-entrypoint \
				docker-php-ext-* \
				docker-php-source \
				"$version/$suite/$variant/"

			has_patches=no
			for p in *.patch ; do
				pv="${p}"
				pv="${pv##php}"
				pmin="${pv%%-*}"
				pv="${pv##${pmin}-}"
				pmax="${pv%%_*}"
				pcur="${version/./}"
				if [ $pmin -le $pcur ] && [ $pcur -le $pmax ]; then
					cp "$p" "$version/$suite/$variant/"
					has_patches=yes
				fi
			done
			if [ "$has_patches" = 'no' ]; then
				sed -ri \
					-e '/##<has-patches>##/,/##<\/has-patches>##/d' \
					"$version/$suite/$variant/Dockerfile"
			fi

			if [ "$versionId" -ge 50600 ]; then
				# PHP 7 uses OpenSSL 1.1, while PHP 5 uses OpenSSL 1.0.
				# For PHP 5.6, we patch it to support OpenSSL 1.1, but for
				# lower versions we build OpenSSL 1.0.
				sed -ri \
					-e '/##<openssl10>##/,/##<\/openssl10>##/d' \
					"$version/$suite/$variant/Dockerfile"
			else
				sed -ri \
					-e '/##<openssl11>##/,/##<\/openssl11>##/d' \
					"$version/$suite/$variant/Dockerfile"
			fi

			if [ "$variant" = 'apache' ]; then
				cp -a apache2-foreground "$version/$suite/$variant/"
			fi
			if [ "$versionId" -lt '70200' ]; then
				# argon2 password hashing is only supported in 7.2+
				sed -ri \
					-e '/##<argon2-stretch>##/,/##<\/argon2-stretch>##/d' \
					-e '/argon2/d' \
					"$version/$suite/$variant/Dockerfile"
			elif [ "$suite" != 'stretch' ]; then
				# and buster+ doesn't need to pull argon2 from stretch-backports
				sed -ri \
					-e '/##<argon2-stretch>##/,/##<\/argon2-stretch>##/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$versionId" -lt '70400' ]; then
				# oniguruma is part of mbstring in php 7.4+
				sed -ri \
					-e '/oniguruma-dev|libonig-dev/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$versionId" -ge '80000' ]; then
				# 8 and above no longer include pecl/pear (see https://github.com/docker-library/php/issues/846#issuecomment-505638494)
				sed -ri \
					-e '/pear |pearrc|pecl.*channel/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$versionId" -lt '70400' ]; then
				# --with-pear is only relevant on PHP 7.4+ (see https://github.com/docker-library/php/issues/846#issuecomment-505638494)
				sed -ri \
					-e '/--with-pear/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$versionId" -lt '70200' ]; then
				# sodium is part of php core 7.2+ https://wiki.php.net/rfc/libsodium
				sed -ri '/sodium/d' "$version/$suite/$variant/Dockerfile"
			fi
			if [ "$variant" = 'fpm' -a "$versionId" -lt '70300' ]; then
				# php-fpm "decorate_workers_output" is only available in 7.3+
				sed -ri \
					-e '/decorate_workers_output/d' \
					-e '/log_limit/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$suite" = 'stretch' ] || [ "$versionId" -ge '70400' ]; then
				# https://github.com/docker-library/php/issues/865
				# https://bugs.php.net/bug.php?id=76324
				# https://github.com/php/php-src/pull/3632
				# https://github.com/php/php-src/commit/2d03197749696ac3f8effba6b7977b0d8729fef3
				sed -ri \
					-e '/freetype-config/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [[ "$suite" == alpine* ]] && [ "$versionId" -lt '70400' ]; then
				# https://github.com/docker-library/php/issues/888
				sed -ri \
					-e '/linux-headers/d' \
					"$version/$suite/$variant/Dockerfile"
			fi
			if [ "$versionId" -lt '80000' ]; then
				# https://github.com/php/php-src/commit/161adfff3f437bf9370e037a9e2bf593c784ccff
				sed -ri \
					-e 's/--enable-zts/--enable-maintainer-zts/g' \
					"$version/$suite/$variant/Dockerfile"
			fi

			# remove any _extra_ blank lines created by the deletions above
			gawk '
				{
					if (NF == 0 || (NF == 1 && $1 == "\\")) {
						blank++
					}
					else {
						blank = 0
					}

					if (blank < 2) {
						print
					}
				}
			' "$version/$suite/$variant/Dockerfile" > "$version/$suite/$variant/Dockerfile.new"
			mv "$version/$suite/$variant/Dockerfile.new" "$version/$suite/$variant/Dockerfile"

			sed -ri \
				-e 's!%%DEBIAN_TAG%%!'"$suite-slim"'!' \
				-e 's!%%DEBIAN_SUITE%%!'"$suite"'!' \
				-e 's!%%ALPINE_VERSION%%!'"$alpineVer"'!' \
				"$version/$suite/$variant/Dockerfile"
			dockerfiles+=( "$version/$suite/$variant/Dockerfile" )
		done
	done

	(
		set -x
		sed -ri \
			-e 's!%%PHP_VERSION%%!'"$fullVersion"'!' \
			-e 's!%%GPG_KEYS%%!'"$gpgKey"'!' \
			-e 's!%%PHP_URL%%!'"$url"'!' \
			-e 's!%%PHP_ASC_URL%%!'"$ascUrl"'!' \
			-e 's!%%PHP_SHA256%%!'"$sha256"'!' \
			-e 's!%%PHP_MD5%%!'"$md5"'!' \
			-e 's!%%PHP_DEBUG%%!'"$([[ ${variant##*-} = debug ]] && echo "yes" || echo "no" )"'!' \
			"${dockerfiles[@]}"
	)

	# update entrypoint commands
	for dockerfile in "${dockerfiles[@]}"; do
		cmd="$(awk '$1 == "CMD" { $1 = ""; print }' "$dockerfile" | tail -1 | jq --raw-output '.[0]')"
		entrypoint="$(dirname "$dockerfile")/docker-php-entrypoint"
		sed -i 's! php ! '"$cmd"' !g' "$entrypoint"
	done

	newGithubMatrix=
	for dockerfile in "${dockerfiles[@]}"; do
		dir="${dockerfile%Dockerfile}"
		dir="${dir%/}"
		dir="${dir#$version}"
		dir="${dir#/}"
		suite="${dir%%/*}"
		variant="${dir##*/}"
		newGithubMatrix+='          - { version: "'"$version"'", suite: "'"$suite"'", variant: "'"$variant"'" }\n'
	done
	githubMatrix="$newGithubMatrix$githubMatrix"
done

perl -0777 -i -pe \
	"s/(##<jobs>##\\n).*(^\\s*##<\\/jobs>##)/\$1$githubMatrix\$2/sm" \
	.github/workflows/ci.yml
