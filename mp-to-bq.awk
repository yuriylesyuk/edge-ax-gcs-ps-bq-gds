
#
# awk -f mp-to-bq.awk mp-to-ax-mapping--mp-vs-pg-201807152139.tsv > bq-to-mp-mapping.json
#
BEGIN{


    FS="\t"


    first = 1

    print "["
}

#
#
#    {
#        "ax_mp_host": {
#            "mp": "x-apigee.edge.mp_host"
#        }
#    },

$1 != "" {


    mp_field = substr( $1, 1, index( $1, " ")-1)
    mp_type = substr( $1, index( $1, " ")+1 )
    sub( /,$/, "", mp_type )
    if( mp_type == "timestamp without time zone" ){
        mp_type = "timestamp"
    } 

   if( $2 !~ /^$/ ){


# print mp_field "<"
     bq_field = substr( $2, 1, index( $2, ":")-1)

#       print ">>" bq_field
   if( first  ){

       first = 0
    }else {
        print "    ,"
     }
        print "    {"
        print "        \"" mp_field "\" : {"
        print "            \"mp\": \"" bq_field "\","
        print "            \"mp_type\": \"" mp_type "\""
        print "        }"
        print "    }"

   }
}

END{ 
    print "]"
}