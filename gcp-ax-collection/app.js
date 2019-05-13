const express = require('express')
const app = express()

const gsutil = require('./gsutil')

// example:
//  http://localhost:3000/v1/upload/location
//    ?repo=edge&dataset=api
//    &tenant=edgemicro-internal~prod
//    &relative_file_path=date%3D2016/01/20/file.json.gz
//    &file_content_type=application/gzip

app.get('/v1/upload/location', (req, res) => {
    var repo = req.query.repo;
    var dataset = req.query.dataset
    var tenant = req.query.tenant
    var contentType = req.query.contentType
    var filePath = req.query.relativeFilePath
    

console.log(req.query);

    gsutil.getSignedUrl( repo,dataset, tenant, contentType,  filePath ,function(err,url){
        if(err) {
                console.error('oops', err);
                res.send(500);
        } 

        // response, json: 
        // {
        //    "url": 

        res.status(200).json({url: url});
    });
});

app.listen(3000, () => console.log('Listening on port: 3000'))
