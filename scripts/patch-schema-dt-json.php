<?php
/**
 * Patches vendor/ikkez/f3-schema-builder Schema.php to add DT_JSON
 * (Pathfinder and f3-cortex reference it; f3-schema-builder does not define it.)
 */
$file = $argv[1] ?? '/var/www/html/pathfinder/vendor/ikkez/f3-schema-builder/lib/db/sql/schema.php';
if (!is_readable($file)) {
    fwrite(STDERR, "patch-schema-dt-json: file not found or not readable: $file\n");
    exit(1);
}
$s = file_get_contents($file);

// Already patched?
if (strpos($s, "DT_JSON='JSON'") !== false) {
    echo "DT_JSON already present in $file\n";
    exit(0);
}

// Normalize to \n so patterns match (e.g. Windows checkout)
$s = str_replace("\r\n", "\n", $s);
$s = str_replace("\r", "\n", $s);

// 1) Add const DT_JSON='JSON' after DT_BINARY='BLOB', (tabs: 2 before const members)
$needle1 = "\t\tDT_BINARY='BLOB',\n\n\t\t// column default values";
$repl1   = "\t\tDT_BINARY='BLOB',\n\t\tDT_JSON='JSON',\n\n\t\t// column default values";
if (strpos($s, $needle1) === false) {
    fwrite(STDERR, "patch-schema-dt-json: could not find const block to patch (DT_BINARY)\n");
    exit(1);
}
$s = str_replace($needle1, $repl1, $s);

// 2) Add 'JSON'=>[...] in dataTypes before 'BLOB' (tabs: 3 before 'BLOB', 4 before inner lines)
$needle2 = "\t\t\t'BLOB'=>[\n\t\t\t\t'mysql|odbc|sqlite2?|ibm'=>'blob',";
$repl2   = "\t\t\t'JSON'=>[\n\t\t\t\t'mysql'=>'json',\n\t\t\t\t'pgsql'=>'jsonb',\n\t\t\t\t'sqlite2?'=>'text',\n\t\t\t\t'mssql|sybase|dblib|odbc|sqlsrv'=>'nvarchar(max)',\n\t\t\t\t'ibm'=>'CLOB(2000000000)',\n\t\t\t],\n\t\t\t'BLOB'=>[\n\t\t\t\t'mysql|odbc|sqlite2?|ibm'=>'blob',";
if (strpos($s, $needle2) === false) {
    fwrite(STDERR, "patch-schema-dt-json: could not find dataTypes BLOB entry to patch\n");
    exit(1);
}
$s = str_replace($needle2, $repl2, $s);

if (!file_put_contents($file, $s)) {
    fwrite(STDERR, "patch-schema-dt-json: failed to write $file\n");
    exit(1);
}
echo "Patched DT_JSON into $file\n";
