package com.exco;

import java.io.File;
import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import org.apache.http.HttpResponse;
import org.apache.http.HttpStatus;
import org.apache.http.client.config.RequestConfig;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.methods.HttpUriRequest;
import org.apache.http.concurrent.FutureCallback;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.FileEntity;
import org.apache.http.impl.nio.client.CloseableHttpAsyncClient;
import org.apache.http.impl.nio.client.HttpAsyncClientBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.apigee.datalake.Config;
import com.apigee.datalake.Constants;
import com.apigee.datalake.DataUploader;
import com.apigee.datalake.Utils;

public class EdgeFluentDataUploader implements DataUploader {


    private static final Logger LOGGER = LoggerFactory.getLogger(EdgeFluentDataUploader.class);

    private CloseableHttpAsyncClient httpClient;
    private final String uapCollectionService;
    private HttpPost req = null;
    
    private HttpPost request = null;
    
//    private HttpGet request = null;
//    private HttpPut s3Request = null;
    private String uapBucket;

    public EdgeFluentDataUploader(Config config) {
        // First copy default request config and only overwrite only timeout values
        RequestConfig requestConfig = RequestConfig.copy(RequestConfig.DEFAULT)
                .setConnectionRequestTimeout(config.getConnectionRequestTimeout()*1000)
                .setConnectTimeout(config.getConnectionTimeout()*1000)
                .setSocketTimeout(config.getSocketTimeout()*1000).build();
        httpClient = HttpAsyncClientBuilder.create().setDefaultRequestConfig(requestConfig).build();
        httpClient.start();
        uapCollectionService = config.getUapCollectionService();
    }

    public boolean upload(Config config, File path, boolean isRetry) {
        getLogger().debug("Fluent UAP uploader called for path: {}", path);
        boolean status = true;
        long startTime = System.nanoTime();
        long endTime = 0;
        long totalTime = 0;
        long totalBytes = 0;
        int numFiles = 0;
        uapBucket="";

        String directoryPath = path.toString();
        String directoryName = directoryPath.substring(directoryPath.lastIndexOf("/") + 1); //org~env~{TS} or org~env~{TS}~recovered~{recoveredTS}
        String directoryParts[] = directoryName.split("~");

        String org = directoryParts[0];
        String env = directoryParts[1];
        String timeStamp =  directoryParts[2]; // Timestamp
        String tenant = org + "~" + env;

        DirectoryStream<Path> stream = null;

        try {
            String dateTimePartition = Utils.getDateTimePartitionName(timeStamp, Constants.TIMESTAMP_IN_NAME_FORMAT, Constants.TIMESTAMP_IN_PARTITION_FORMAT);

            stream = Files.newDirectoryStream(path.toPath());
            for (Path filePath : stream) {

                String fileName = filePath.getFileName().toString();
                String relativeFilePath = dateTimePartition + "/" + fileName;

                File file = new File(directoryPath+"/"+fileName);
                FileEntity fileEntity = new FileEntity(file, ContentType.create("application/x-gzip"));

                status = uploadFile(fileName, config.getUapRepository(), config.getUapDataset(), tenant, relativeFilePath, fileEntity);
                if(status == false) {
                    break;
                }
                endTime = System.nanoTime();
                totalTime = TimeUnit.MILLISECONDS.convert(endTime - startTime, TimeUnit.NANOSECONDS);
                totalBytes += Utils.getDirSize(filePath.toAbsolutePath().toString());
                numFiles++;

                if(status == true) {
                    // Keep files in moved folder after a successful upload if isDeleteAfterUpload is set to false
                    if(!config.isDeleteAfterUpload()) {
                        // move only uploaded file to moved folder
                        boolean movedStatus = moveFileToMoved(config, path, file);
                        String movedStr = config.getRootAbsolutePath() + "/" + config.getMovedDir();
                        if(!movedStatus) {
                            getLogger().error("Error moving {} to folder {} ", fileName, movedStr);
                        } else {
                            getLogger().debug("Moved file : {} to {} after successful upload to UAP", fileName, movedStr);
                        }
                    } else {
                        // delete file after successful upload to ensure no retrying of uploaded files
                        Files.delete(file.toPath());
                        LOGGER.debug("Deleted file : {} after successful upload to UAP", file.toPath());
                    }
                }
            }
        } catch (Exception e) {
            getLogger().error("Upload to UAP failed for path: {} Exception: {}", path, e.getMessage());
            status = false;
        } finally {
            // reset requests incase exception occurs
            if(request != null) {
                request.reset();
            }
//            if (s3Request != null) {
//                s3Request.reset();
//            }
            // Close the directory stream else file handles will not be releases
            if(stream != null) {
                try {
                    stream.close();
                } catch (IOException e) {
                    getLogger().warn("Closing directory stream failed {}", e.getMessage());
                }
            }
            // print metrics
            getLogger().info("Uploader Metrics: \n tenant = {} \n" +
                            " bucketTS = {} \n" +
                            " uapBucket = {} \n numFiles = {} \n" +
                            " totalBytes = {} \n totalTime = {} ms",
                    new Object[]{tenant, timeStamp, uapBucket, numFiles, totalBytes, totalTime});
        }
        return status;
    }

    private boolean moveFileToMoved(Config config, File timestampFolder, File file) {
        String movedStr = config.getRootAbsolutePath() + "/" + config.getMovedDir();
        File movedPath = new File(movedStr + "/" + timestampFolder.getName());
        // make the timestamp directory in moved folder if doesnt already exist
        if(!movedPath.exists())
            movedPath.mkdir();

        // Move the file by renaming it
        File movedFile = new File(movedPath + "/" + file.getName());
        return file.renameTo(movedFile);
    }

    private boolean uploadFile(String fileName, String uapRepository, String uapDataset, String tenant,
                               String relativeFilePath, FileEntity fileEntity) throws Exception {
        // Upload file through Edge Fluent collectionService
        boolean status = true;
        
		request = new HttpPost(uapCollectionService);
		// add fileEntity
		request.setEntity(fileEntity);
		request.addHeader("Expect", "100-continue");
		request.addHeader("Content-Encoding", "gzip");
		
		// Upload file to fluent http input
		HttpResponse response = executeHttpRequest(request);
		
		// reset HttpRequests to release the connection
		request.reset();
		request = null;
		if (response != null) {
		  if (response.getStatusLine().getStatusCode() != HttpStatus.SC_OK) {
		      getLogger().error("Upload to CloudStore failed for file: {} \n due to Response : " +
		                      "\n HTTP Status Code: {} \n Error Message: {} ",
		              new Object[]{fileName, response.getStatusLine().getStatusCode(), response.getStatusLine().getReasonPhrase()});
		      status = false;
		  }
		} else {
		  getLogger().error("Upload failed for file: {} as returned response entity for uploading to Fluentd is null", fileName);
		  status = false;
		}

        
//        URI uri = new URIBuilder(uapCollectionService)
//                .addParameter("repo", uapRepository)
//                .addParameter("dataset", uapDataset)
//                .addParameter("tenant", tenant)
//                .addParameter("relativeFilePath", relativeFilePath)
//                .addParameter("contentType", "application/x-gzip")
//                .addParameter("encrypt", "true")        // uap collection service creates sse enabled signed url based on this query param
//                .build();
//        request = new HttpGet(uri);
//        // Get S3 signedURL from uapCollectionService
//        HttpResponse response = executeHttpRequest(request);
//
//        // reset HttpRequests to release the connection
//        request.reset();
//        request = null;
//
//        if (response != null) {
//            if (response.getStatusLine().getStatusCode() == HttpStatus.SC_OK) {
//                // extract signed URL and create a PUT request
//                HttpEntity httpEntity = response.getEntity();
//                if (httpEntity != null) {
//                    // Extract the signurl from the response
//                    JsonElement element = new JsonParser().parse(EntityUtils.toString(httpEntity));
//                    JsonObject jsonObj = element.getAsJsonObject();
//
//                    String url = "";
//                    if (jsonObj.has("url")) {
//                        url = jsonObj.get("url").getAsString();
//                        uapBucket = Utils.getUapBucket(url);
//                    }
//
//                    /* If not url is found, then  url is set to ""
//                    * This will throw an Illegal argument exception, that will be caught above
//                    * the upload will be marked as failed
//                    */
//
//                    s3Request = new HttpPut(url);
//                    // add fileEntity
//                    s3Request.setEntity(fileEntity);
//                    s3Request.addHeader("Expect", "100-continue");
//                    s3Request.addHeader("Content-Type", "application/x-gzip");
//                    // Setting this header on the PUT request tells aws to encrypt the data at on s3 and decrypt it when GET on the object is performed
//                    s3Request.addHeader("x-amz-server-side-encryption", "AES256");
//
//                    // Upload file to s3 using signed URL
//                    HttpResponse s3Response = executeHttpRequest(s3Request);
//
//                    // reset HttpRequests to release the connection
//                    s3Request.reset();
//                    s3Request = null;
//                    if (s3Response != null) {
//                        if (s3Response.getStatusLine().getStatusCode() != HttpStatus.SC_OK) {
//                            getLogger().error("Upload to CloudStore failed for file: {} \n due to Response : " +
//                                            "\n HTTP Status Code: {} \n Error Message: {} ",
//                                    new Object[]{fileName, s3Response.getStatusLine().getStatusCode(), s3Response.getStatusLine().getReasonPhrase()});
//                            status = false;
//                        }
//                    } else {
//                        getLogger().error("Upload failed for file: {} as returned response entity for uploading to S3 is null", fileName);
//                        status = false;
//                    }
//                } else {
//                    getLogger().error("Upload failed for file: {} as returned httpEntity for getting signed URL is null", fileName);
//                    status = false;
//                }
//            } else {
//                getLogger().error("Upload to UAP failed for file: {} \n due to Response : " +
//                                "\n HTTP Status Code: {} \n Error Message: {} ",
//                        new Object[]{fileName, response.getStatusLine().getStatusCode(), response.getStatusLine().getReasonPhrase()});
//                status = false;
//            }
//        } else {
//            getLogger().error("Upload failed for file: {} as returned response entity for getting signed URL is null", fileName);
//            status = false;
//        }

        return status;
    }

    private HttpResponse executeHttpRequest(final HttpUriRequest httpUriRequest) throws ExecutionException, InterruptedException {
        HttpResponse response = null;
        Future<HttpResponse> responseFuture = httpClient.execute(httpUriRequest, new FutureCallback<HttpResponse>() {
            public void completed(final HttpResponse response2) {}

            public void failed(final Exception e) {}

            public void cancelled() {
                getLogger().warn("Upload task timed out so aborting request {}", httpUriRequest.getURI());
            }
        });

        try {
            response  = responseFuture.get(Constants.TASK_TIMEOUT, TimeUnit.SECONDS);
        } catch (TimeoutException e) {
            responseFuture.cancel(true);
        }
        return  response;
    }

    @Override
    public void shutdown() {
        try {
            httpClient.close();
        } catch (IOException e) {
            getLogger().warn("Exception occurred while closing CloseableHttpClient in UAPUploader");
        }
    }

    protected Logger getLogger() {
        return LOGGER;
    }

}
