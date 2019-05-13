/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.exco.ax.dataflows.gcstopb;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.channels.Channels;
import java.nio.channels.ReadableByteChannel;

import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.io.FileIO;
import org.apache.beam.sdk.io.gcp.pubsub.PubsubIO;
import org.apache.beam.sdk.io.gcp.pubsub.PubsubMessage;
import org.apache.beam.sdk.options.Description;
import org.apache.beam.sdk.options.PipelineOptions;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.options.ValueProvider;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.ParDo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.gson.JsonElement;
import com.google.gson.JsonParser;

/**
 * Dataflow for processing uploaded file in GPS to transfer its contents into PubSub Topic.
 *
 * <p>The example takes two strings, converts them to their upper-case
 * representation and logs them.
 *
 * <p>To run this starter example locally using DirectRunner, just
 * execute it without any additional parameters from your favorite development
 * environment.
 *
 * <p>To run this starter example using managed resource in Google Cloud
 * Platform, you should specify the following command-line options:
 *   --project=<YOUR_PROJECT_ID>
 *   --stagingLocation=<STAGING_LOCATION_IN_CLOUD_STORAGE>
 *   --runner=DataflowRunner
 */
public class EdgeAXGcsToPubSub {
  private static final Logger LOG = LoggerFactory.getLogger(EdgeAXGcsToPubSub.class);

  
  
  /**
   * The {@link Options} class provides the custom execution options passed by the executor at the
   * command-line.
   */
  public interface Options extends PipelineOptions {
    @Description("Pub/Sub topic to read the uploaded bucket/filename GCS notifications")
    ValueProvider<String> getInputTopic();

    void setInputTopic(ValueProvider<String> value);

    @Description("Pub/Sub topic for Analytics raw records")
    ValueProvider<String> getOutputTopic();

    void setOutputTopic(ValueProvider<String> value);

// TODO: add dl processing
    @Description(
        "The dead-letter table to output to within BigQuery in <project-id>:<dataset>.<table> "
            + "format. If it doesn't exist, it will be created during pipeline execution.")
    ValueProvider<String> getOutputDeadletterTable();

    void setOutputDeadletterTable(ValueProvider<String> value);
  }  

  
  public static void main(String[] args) {
	  
	  
	  
	Options options = PipelineOptionsFactory.fromArgs(args).withValidation().as(Options.class);

	Pipeline p = Pipeline.create( options );  
    
    
    

    p.apply("Read Notification", PubsubIO.readMessagesWithAttributes()
                 .fromTopic( options.getInputTopic() )
    		)

    
    
// TODO: add error processing

    .apply("Transform JSON Payload", ParDo.of(new DoFn<PubsubMessage, String>() {
        @ProcessElement
        public void processElement(ProcessContext c)  {
  		  LOG.info( c.element().toString() );
		  
		  LOG.info( new String(c.element().getPayload()) );
		  
		  
		  JsonParser parser = new JsonParser();
          
		  JsonElement jsonTree = parser.parse(new InputStreamReader( new ByteArrayInputStream( c.element().getPayload() ) ) );
		
		  String bucket = jsonTree.getAsJsonObject().get("bucket").getAsString();
		  String name = jsonTree.getAsJsonObject().get("name").getAsString();
		  
		  c.output("gs://" + bucket + "/" + name);
          
        }      
        
        
        
    }))
    
    .apply(FileIO.matchAll())
    
    .apply(FileIO.readMatches())
    
    .apply("Read File in Notification", ParDo.of(new DoFn<FileIO.ReadableFile, String>() {
        @ProcessElement
        public void processElement(ProcessContext c) throws IOException {
    
        	LOG.info( c.element().toString() );
        	
        	FileIO.ReadableFile f = c.element();
        	
            ReadableByteChannel readableByteChannel = null;
            InputStream inputStream = null;
            BufferedReader bufferedReader = null;
            try {
                //  
                readableByteChannel = f.open();
                inputStream = Channels.newInputStream(readableByteChannel);
                bufferedReader = new BufferedReader(new InputStreamReader(inputStream, "UTF-8"));
                String line;
                while ((line = bufferedReader.readLine()) != null) {
                    if (line.length() > 1) {
                    	
                    	c.output( line );
                    }
                }
            } catch (IOException ex) {
                LOG.error("Exception during reading the file: {}", ex);
            } finally {
                //IOUtils.closeQuietly(bufferedReader);
                //IOUtils.closeQuietly(inputStream);
            }
        	
        	
            readableByteChannel.close();
        }
    }))
    
    	.apply("WriteItemsToTopic", PubsubIO.writeStrings().to( 
    			options.getOutputTopic() 
    ));

    p.run();
  }
}
