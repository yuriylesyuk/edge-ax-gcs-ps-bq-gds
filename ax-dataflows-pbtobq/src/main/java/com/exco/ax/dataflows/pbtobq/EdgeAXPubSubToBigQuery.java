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
package com.exco.ax.dataflows.pbtobq;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.sql.Timestamp;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.coders.Coder;
import org.apache.beam.sdk.io.gcp.bigquery.BigQueryIO;
import org.apache.beam.sdk.io.gcp.bigquery.TableRowJsonCoder;
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

import com.google.api.services.bigquery.model.TableRow;


/**
 * A starter example for writing Beam programs.
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
public class EdgeAXPubSubToBigQuery {
  private static final Logger LOG = LoggerFactory.getLogger(EdgeAXPubSubToBigQuery.class);

  
  /**
   * The {@link Options} class provides the custom execution options passed by the executor at the
   * command-line.
   */
  public interface Options extends PipelineOptions {
    @Description("Table spec to write the output to")
    ValueProvider<String> getOutputTableSpec();

    void setOutputTableSpec(ValueProvider<String> value);

    @Description("Pub/Sub topic to read the input from")
    ValueProvider<String> getInputTopic();

    void setInputTopic(ValueProvider<String> value);

    @Description(
        "The dead-letter table to output to within BigQuery in <project-id>:<dataset>.<table> "
            + "format. If it doesn't exist, it will be created during pipeline execution.")
    ValueProvider<String> getOutputDeadletterTable();

    void setOutputDeadletterTable(ValueProvider<String> value);
  }  
  
  public static void main(String[] args) {
	  
	final Map<String, String> bqmap =  new HashMap<String, String>();
	final List<Map<String, Map<String, String>>> json =  new BqMapping().LoadMapping("bq-to-mp-mapping.json", bqmap);
		
	 
	Options options = PipelineOptionsFactory.fromArgs(args).withValidation().as(Options.class);
	
	 
    Pipeline p = Pipeline.create( options );


    p.apply("Read From Pubsub", PubsubIO.readMessagesWithAttributes()
                 .fromTopic( options.getInputTopic() )
    		)
    
    
    .apply("Transform JSON Payload", ParDo.of(new DoFn<PubsubMessage, TableRow>() {
      @ProcessElement
      public void processElement(ProcessContext c)  {
        LOG.info(c.element().toString());
        
        
        PubsubMessage message = c.element();
        
        TableRow t =  	new TableRow();
        		
        		try {
					t = TableRowJsonCoder.of().decode(new ByteArrayInputStream(message.getPayload()), Coder.Context.OUTER);
				} catch (IOException e) {
					// TODO Auto-generated catch block
					e.printStackTrace();
				}
        		
                
                TableRow tt = new TableRow();
//                tt.put("proxy_basepath", t.get( "proxy_basepath"));
                
                if(t.get("proxy_basepath") != null ) tt.put("proxy_basepath",t.get( "proxy_basepath") );
                
                
                for( Map<String, Map<String,String>> map : json ) {
    				for (Map.Entry<String, Map<String,String>> entry : map.entrySet()) {
    			        
    					String src = entry.getKey();
    					String tgt = entry.getValue().get("mp") == null ? src : entry.getValue().get("mp");
    					String type = entry.getValue().get("mp_type") == null ? src : entry.getValue().get("mp_type");
    					
    					if(t.get( src ) != null ) {
    						
    						// TODO: Generalize, currently for is_error
    						// t t.put("is_error", ((Boolean)t.get( "is_error")).booleanValue() ? 1 : 0);
    						//if( src.equals("is_error") ) {
    						//	tt.put( tgt, ((Boolean)t.get( src )).booleanValue() ? 1 : 0) ;
    							
    						//}else {
    						if( type.equals("timestamp") ) {
    							tt.put( tgt,  ((Long)t.get(src) ).doubleValue()/1000 );
    							
    						}else {
    						
    							tt.put( tgt, t.get( src) );
    						}
    					}
    					
    					

    				}
    				
    			};
                
                
                
                
                c.output(tt);
                LOG.info("here");  
               
      }
    }))
    
    
    

    .apply("WriteBigQuery", BigQueryIO.writeTableRows()
    		//.withoutValidation()
            .withCreateDisposition(BigQueryIO.Write.CreateDisposition.CREATE_NEVER)
            .withWriteDisposition(BigQueryIO.Write.WriteDisposition.WRITE_APPEND)
    
            .to( options.getOutputTableSpec() )
    );
    
    p.run();
  }
}


