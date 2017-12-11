#/usr/local/bin bash
#
#  Licensed to the Apache Software Foundation (ASF) under one or more
#  contributor license agreements.  See the NOTICE file distributed with
#  this work for additional information regarding copyright ownership.
#  The ASF licenses this file to You under the Apache License, Version 2.0
#  (the "License"); you may not use this file except in compliance with
#  the License.  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#
shopt -s nocasematch

METRON_DIST="https://dist.apache.org/repos/dist/dev/metron/"

if [ "$#" -ne 3 ]; then
    echo "error: missing arguments"
    echo "$0 [METRON VERSION][RC#][METRON BRO PLUGIN VERSION]"
    exit 1
else
    if [[ "$1" =~ ^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2} ]]; then
       METRON_VERSION="$1"
    else
       echo "[ERROR] $1 may not be a valid version number"
       exit 1
    fi
    if [[ "$2" =~ ^RC[0-9]+ ]]; then
      RC=$(echo "$2" | tr '[:upper:]' '[:lower:]')
      UPPER_RC=$(echo "$2" | tr '[:lower:]' '[:upper:]')
    elif [[ "$2" =~ ^[0-9]+ ]]; then
      #statements
      RC=rc"$2"
      UPPER_RC=RC"$2"
    else
      echo "[ERROR] invalid RC, valid is RC# or just #"
      exit 1
    fi
    if [[ "$3" =~ ^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,2} ]]; then
       BRO_VERSION="$3"
    else
       echo "[ERROR] $3 may not be a valid version number"
       exit 1
    fi
fi

echo "Metron Version $METRON_VERSION"
echo "Release Canidate $RC"

METRON_RC_DIST="$METRON_DIST$METRON_VERSION-$UPPER_RC"
echo "Metron RC Distribution Root is $METRON_RC_DIST"

# working directory
WORK=~/tmp/metron-$METRON_VERSION-$RC

# handle tilde expansion
WORK="${WORK/#\~/$HOME}"

# warn the user if the working directory exists
if [ -d "$WORK" ]; then
  echo "[ERROR] Directory $WORK exists, please rename it and start over"
  exit 1
fi

if [ ! -d "$WORK" ]; then
  mkdir -p $WORK
fi
echo "Working directory $WORK"

KEYS="$METRON_RC_DIST/KEYS"
METRON_ASSEMBLY="$METRON_RC_DIST/apache-metron-$METRON_VERSION-$RC.tar.gz"
METRON_ASSEMBLY_SIG="$METRON_ASSEMBLY.asc"
METRON_KAFKA_BRO_ASSEMBLY="$METRON_RC_DIST/apache-metron-bro-plugin-kafka_$BRO_VERSION.tar.gz"
METRON_KAFKA_BRO_ASSEMBLY_ASC="$METRON_KAFKA_BRO_ASSEMBLY.asc"

# SHOULD BE FUNCTION
echo "Downloading $KEYS"
wget -P "$WORK" "$KEYS"
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download $KEYS"
  exit 1
fi

echo "Downloading $METRON_ASSEMBLY"
wget -P $WORK $METRON_ASSEMBLY
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download $METRON_ASSEMBLY"
  exit 1
fi
echo "Downloading $METRON_ASSEMBLY_SIG"
wget -P $WORK $METRON_ASSEMBLY_SIG
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download $METRON_ASSEMBLY_SIG"
  exit 1
fi
echo "Downloading $METRON_KAFKA_BRO_ASSEMBLY"
wget -P $WORK $METRON_KAFKA_BRO_ASSEMBLY
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download $METRON_KAFKA_BRO_ASSEMBLY"
  exit 1
fi
echo "Downloading $METRON_KAFKA_BRO_ASSEMBLY_ASC"
wget -P $WORK $METRON_KAFKA_BRO_ASSEMBLY_ASC
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to download $METRON_KAFKA_BRO_ASSEMBLY_ASC"
  exit 1
fi

cd $WORK
echo "importing metron keys"

gpg --import KEYS

if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed to import KEYS"
  exit 1
fi

echo "Verifying Metron Assembly"
gpg --verify ./"apache-metron-$METRON_VERSION-$RC.tar.gz.asc" "apache-metron-$METRON_VERSION-$RC.tar.gz"
if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed to verify Metron Assembly"
  exit 1
fi

echo "Verifying Bro Kafka Plugin Assembly"
gpg --verify ./"apache-metron-bro-plugin-kafka_$BRO_VERSION.tar.gz.asc" "apache-metron-bro-plugin-kafka_$BRO_VERSION.tar.gz"
if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed to verify Bro Kafka Plugin Assembly"
  exit 1
fi

echo "Unpacking Assemblies"
tar -xzf "apache-metron-$METRON_VERSION-$RC.tar.gz"
if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed to unpack Metron Assembly"
  exit 1
fi

tar -xzf "apache-metron-bro-plugin-kafka_$BRO_VERSION.tar.gz"
if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed to unpack  Bro Kafka Plugin Assembly"
  exit 1
fi
#ask if build and test METRON
# run tests?
echo ""
echo ""
read -p "  run test suite [install, unit tests, integration tests, ui tests, licenses, rpm build]? [yN] " -n 1 -r
echo
DID_BUILD=0
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "LOG will be created in $WORK"
  cd "apache-metron-$METRON_VERSION-$RC"
  mvn -q -T 2C -DskipTests clean install  | tee ../build-install.log &&
    mvn -q -T 2C surefire:test@unit-tests | tee ../build-unit-tests.log &&
    mvn -q surefire:test@integration-tests | tee ../build-integration-tests.log &&
    mvn -q test --projects metron-interface/metron-config | tee ../build-metron-config-tests.log &&
    build_utils/verify_licenses.sh | tee ../build-lic.log &&
    cd metron-deployment &&
    mvn -q package -DskipTests -P build-rpms | tee ../build-rpm.log &&
    cd ..
    DID_BUILD=1
fi
if [[ $? -ne 0 ]]; then
  echo "[ERROR] failed test suite"
  exit 1
fi

#ask if build test vagrant METRON

# run tests?
echo ""
echo ""
read -p "  run vagrant full_dev? [yN] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  cd "$WORK/apache-metron-$METRON_VERSION-$RC/metron-deployment/vagrant/full-dev-platfrom
  if [[ $DID_BUILD -ne 1 ]]; then
    vagrant up
  else
    vagrant --ansible-skip-tags="build,sensors,quick-dev" up
  fi
fi
