
# bq mk --table mydataset.mytable ./ax-tlab.json

BEGIN{


    intable = 0;
    lineone = 1;
    linesep = "";
}


intable == 1 && $0 ~ /^\);/ {
    intable = 0
    print "]"
    print "}"
}


#   {
#         "description": "quarter",
#       "mode": "REQUIRED",
#       "name": "qtr",
#       "type": "STRING"
#   },

intable == 1 {

    print linesep

    if( lineone == 1 ){
        linesep =  "\t\t,"
        lineone = 0
    }

    type = $2
    sub( /,/, "", type)



    print "\t{"
    print "\t\t" "\"description\": " "\"description "  $1 "\","
    #print "\t\t" "\"mode\": " "\"Nullable\","
    print "\t\t" "\"name\":  " "\"" $1  "\""  "," 
    print "\t\t" "\"type\": " "\"" totype( type ) "\""
    print "\t}"
}

function totype ( type ){
    if( type == "text" ){
        return "string"
    }else if( type == "bigint" ){
        return "integer"
    }else if( type == "real" ){
        return "numeric"
    }
    return type
}


/CREATE TABLE/{
    intable = 1;

##    print $0

    # bq mk --table " " [PROJECT_ID]:[DATASET]." $3 " [PATH_TO_SCHEMA_FILE]
    print "{ \"BigQuery Schema\": ["

}

  