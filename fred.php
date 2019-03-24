<?php

global $name;

$name    = 'SGW_LetsEncrypt';

function execute($cmd) {
    echo $cmd . PHP_EOL;
    $f = popen($cmd, 'r');
    while (!feof($f)) {
        echo fread($f, 1024);
    }
    $result = pclose($f);
    if ($result !== 0) {
        throw new \Exception("Task failed");
    }
}

$fred->task('db-backup', function () use ($fred) {
    $user = getenv('USER');
    $password_db = getenv('password_db');
    execute("/usr/bin/mysqldump -u $user --password=$password_db imscp | gzip > data/imscp_dev.sql.gz");
});

$fred->task('package-zip', function () use ($fred) {
    global $name;
    execute("rm -f *.zip && zip -r -x@./upload-exclude-zip.txt -y -q ./$name.zip .");
});

$fred->task('package-tar', function () use ($fred) {
    global $name;
    execute("rm -f *.tgz && tar -cvzf ./$name.tgz --transform 's|./|$name/|' -X upload-exclude.txt ./*");
});

$fred->task('package', function () use ($fred) {
    // Note: Only tgz / bzip2 are supported for upload as iMSCP plugins
    // $fred->execute('package-zip');
    $fred->execute('package-tar');
});

