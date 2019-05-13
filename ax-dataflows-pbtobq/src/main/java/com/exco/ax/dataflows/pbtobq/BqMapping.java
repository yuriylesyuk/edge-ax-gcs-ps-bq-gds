package com.exco.ax.dataflows.pbtobq;

import java.io.FileNotFoundException;
import java.io.FileReader;
import java.lang.reflect.Type;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.common.reflect.TypeToken;
import com.google.gson.Gson;
import com.google.gson.JsonIOException;
import com.google.gson.JsonSyntaxException;

public class BqMapping {
	  private static final Logger LOG = LoggerFactory.getLogger(BqMapping.class);

	
	  public List<Map<String, Map<String, String>>>  LoadMapping( String fileName,  Map<String, String> bqmap ) {
		
		  
		  
		
		Type mapping = new TypeToken<List<Map<String, Map<String,String>>>>(){
			private static final long serialVersionUID = -6911116058196364023L;
		}.getType();  
		
		
		List<Map<String, Map<String, String>>> json = null;
		
		try {
			ClassLoader classLoader = new BqMapping().getClass().getClassLoader();
			
			json = new Gson().fromJson( new FileReader( classLoader.getResource(fileName).getFile() ), mapping);
			 
			for( Map<String, Map<String,String>> map : json ) {
				for (Map.Entry<String, Map<String,String>> entry : map.entrySet()) {
					LOG.info( " Loading: " + entry.getKey() + " -> " + entry.getValue());
			        
			        bqmap.put(entry.getKey(), entry.getValue().get("bq"));

				}
				
			};
			
			
		} catch (JsonIOException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (JsonSyntaxException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		} catch (FileNotFoundException e) {
			// TODO Auto-generated catch block
			e.printStackTrace();
		}
		
		return json; 

	}


	public static void main(String[] args) {
		Map<String, String> bqmap =  new HashMap<String, String>();
		List<Map<String, Map<String, String>>> json = null;
		
		
		json = new BqMapping().LoadMapping("bq-to-mp-mapping.json", bqmap);
		
		
		LOG.info( "here: " + bqmap.get("ax_mp_host"));
		
	}
	
}
