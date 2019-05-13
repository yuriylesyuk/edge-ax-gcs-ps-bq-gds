const Storage = require('@google-cloud/storage');

const fs = require('fs');
const ini = require('ini')

const config = ini.parse(fs.readFileSync('./gcp-ax-collection.ini', 'utf-8'))

const storage = new Storage({
    keyFilename: config.privatekey
  });

const bucketid = config.bucket 

exports.getSignedUrl = function( repo, dataset, tenant, contentType, filePath, callback ){
    var bucket = storage.bucket( bucketid );

    var file = bucket.file( repo + "/" + dataset + "/" + filePath );
console.log("repo: " + repo);

    // url = gcsSignedUrlGenerator
    // .httpMethod("PUT")
    // .bucket(gcsBucket)
    // .pathInBucket(pathKey)
    // .contentType(contentType)
    // .generate();

    var expires = new Date();
    expires = expires.setSeconds( expires.getSeconds() + 60 );

    var config = {
        action: 'write',
        contentType: contentType,
        expires: expires
    };
    
    file.getSignedUrl(config, function(err, url) {
    if (err) {
        console.error(err);
        return;
    }

        console.log( url );

        callback( null, url );
    });
   
}
