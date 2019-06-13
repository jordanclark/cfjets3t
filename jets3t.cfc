component {

	function init(
		required string accessKeyId
	,	required string secretAccessKey
	,	numeric httpTimeOut= 300
	,	string endPoint= ""
	,	boolean debug= ( request.debug ?: false )
	) {
		variables.epoch= dateConvert( "utc2Local", "January 1 1970 00:00" );
		this.accessKeyId= arguments.accessKeyId;
		this.secretAccessKey= arguments.secretAccessKey;
		this.httpTimeOut= arguments.httpTimeOut;
		this.debug= arguments.debug;
		this.mimeTypes= {
			htm= "text/html"
		,	html= "text/html"
		,	js= "application/x-javascript"
		,	txt= "text/plain"
		,	xml= "text/xml"
		,	rss= "application/rss+xml"
		,	css= "text/css"
		,	gz= "application/x-gzip"
		,	gif= "image/gif"
		,	jpe= "image/jpeg"
		,	jpeg= "image/jpeg"
		,	jpg= "image/jpeg"
		,	png= "image/png"
		,	swf= "application/x-shockwave-flash"
		,	ico= "image/x-icon"
		,	flv= "video/x-flv"
		,	doc= "application/msword"
		,	xls= "application/vnd.ms-excel"
		,	pdf= "application/pdf"
		,	htc= "text/x-component"
		,	svg= "image/svg+xml"
		,	eot= "application/vnd.ms-fontobject"
		,	ttf= "font/ttf"
		,	otf= "font/opentype"
		,	woff= "application/font-woff"
		,	woff2= "font/woff2"
		};
		this.countGet= 0;
		this.countRequest= 0;
		this.randomPropName= "props" & hash( arguments.accessKeyID & arguments.secretAccessKey );
		
		this.cred= createObject( "java", "org.jets3t.service.security.AWSCredentials" ).init( arguments.accessKeyId, arguments.secretAccessKey );
		this.staticProps= createObject( "java", "org.jets3t.service.Jets3tProperties" ).getInstance( createObject( "java", "org.jets3t.service.Constants" ).JETS3T_PROPERTIES_FILENAME );
		this.staticProps.clearAllProperties();
		this.props= createObject( "java", "org.jets3t.service.Jets3tProperties" ).init();
		this.props.loadAndReplaceProperties( this.staticProps, this.randomPropName );
		this.props.setProperty( "s3service.https-only", true );
		if ( len( arguments.endPoint ) ) {
			this.props.setProperty( "s3service.s3-endpoint", arguments.endPoint );
			this.props.setProperty( "s3service.disable-dns-buckets", true );
			this.props.setProperty( "s3service.enable-storage-classes", false );
		}
		this.s3= createObject( "java", "org.jets3t.service.impl.rest.httpclient.RestS3Service" ).init( this.cred, "CF JetS3t Wrapper", javaCast( "null", 0 ), this.props );
		this.aclObj= createObject( "java", "org.jets3t.service.acl.AccessControlList" ).init();
		this.utils= createObject( "java", "org.jets3t.service.utils.ServiceUtils" ).init();

		// method renaming 
		this.listBuckets= this.getBuckets;
		this.listObjects= this.getBucket;
		this.createBucket= this.putBucket;
		this.createObject= this.putObject;
		this.createFile= this.putFileObject;
		this.createFileObject= this.putFileObject;
		this.createFileObjects= this.putFileObjects;

		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "cfJetS3t: " & arguments.input );
			} else {
				request.log( "cfJetS3t: (complex type)" );
				request.log( arguments.input );
			}
		} else if( this.debug ) {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="cfJetS3t", type="information" );
		}
		return;
	}

	string function getFileMimeType( required string filePath ) {
		var contentType= "";
		if ( !len( arguments.filePath ) ) {
			// do nothing 
		} else if ( structKeyExists( this.mimeTypes, listLast( arguments.filePath, "." ) ) ) {
			contentType= this.mimeTypes[ listLast( arguments.filePath, "." ) ];
		} else {
			try {
				contentType= getPageContext().getServletContext().getMimeType( arguments.filePath );
			} catch (any cfcatch) {
				contentType= "";
			}
			if ( !isDefined( "contentType" ) ) {
				contentType= "";
			}
		}
		return contentType;
	}

	private string function nullif( required string value, check= "" ) {
		return ( isNull( arguments.value ) || arguments.value == arguments.check ? javaCast( "null", 0 ) : arguments.value );
	}

	/**
	 * @description List all available buckets.
	 */
	function getBuckets() {
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			out.buckets= this.s3.listAllBuckets();
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "errorMessage" ) ) {
				out.errorDetail= cfcatch.errorMessage;
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Creates a bucket.
	 */
	function putBucket( required string bucket, string acl= "private", string location= "" ) {
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "S3 PUT [#arguments.bucket#]" );

		if ( arguments.acl == "public-read" ) {
			arguments.acl= this.aclObj.REST_CANNED_PUBLIC_READ;
		} else if ( arguments.acl == "public-read-write" ) {
			arguments.acl= this.aclObj.REST_CANNED_PUBLIC_READ_WRITE;
		} else if ( arguments.acl == "auth-read" ) {
			arguments.acl= this.aclObj.REST_CANNED_AUTHENTICATED_READ;
		} else { // private 
			arguments.acl= this.aclObj.REST_CANNED_PRIVATE;
		}
		arguments.location= this.nullif( arguments.location );

		try {
			out.bucket= this.s3.createBucket( arguments.bucket, arguments.location, arguments.acl );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Get a bucket.
	 */
	function getBucket(
		required string bucket
	,	string prefix= ""
	,	string marker= ""
	,	numeric maxKeys= 1000
	,	string delimiter= ""
	,	boolean all= true
	,	boolean detail= false
	) {
		var item= "";
		var out= {
			success= false
		,	contents= []
		,	prefixes= []
		,	truncated= false
		};
		this.debugLog( "S3 GET [#arguments.bucket#][#arguments.maxKeys#]" );
		try {
			var cmd= this.s3.listObjectsChunked(
				arguments.bucket
			,	this.nullif( arguments.prefix )
			,	this.nullif( arguments.delimiter )
			,	this.nullif( arguments.maxKeys )
			,	this.nullif( arguments.marker )
			,	arguments.all
			);
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		if ( out.success ) {
			if ( arguments.detail ) {
				for ( item in cmd.getObjects() ) {
					arrayAppend( out.contents, {
						url= "http://s3.amazonaws.com/#item.getBucketName()#/#item.getKey()#"
					,	bucket= item.getBucketName()
					,	key= item.getKey()
					,	storageClass= item.getStorageClass()
					,	version= ( isDefined( item.getVersionId() ) ? item.getVersionId() : "" )
					,	LastModified= item.getLastModifiedDate()
					,	metadata= item.getModifiableMetadata()
					,	size= item.getContentLength()
					,	eTag= item.getETag()
					,	ownerID= item.getOwner().getId()
					,	owner= item.getOwner().getDisplayName()
					} );
				}
			} else {
				for ( item in cmd.getObjects() ) {
					arrayAppend( out.contents, item.getKey() );
				}
			}
			out.truncated= ( !cmd.isListingComplete() );
			out.prefixes= cmd.getCommonPrefixes();
		}
		return out;
	}

	/**
	 * @description Get a bucket.
	 */
	function getBucketACL( required string bucket ) {
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			out.acl= this.s3.getBucketACL( arguments.bucket );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Deletes a bucket.
	 */
	function deleteBucket( required string bucket ) {
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "S3 DELETE [#arguments.bucket#]" );
		try {
			this.s3.deleteBucket( arguments.bucket );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Puts an object into a bucket.
	 */
	function putFileObject(
		required string bucket
	,	required string key
	,	required string file
	,	string type= "auto"
	,	string disposition= ""
	,	string encoding= ""
	,	string acl= "private"
	,	numeric maxAge= 0
	,	string expires= ""
	,	struct metaData= {}
	,	string storage= ""
	) {
		var obj= 0;
		var item= "";
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "S3 PUT [#arguments.bucket#][#arguments.key#]= #arguments.file#" );
		try {
			if ( left( arguments.file, 3 ) == "RAM" ) {
				// read VFS file and pass in as bytes instead 
				var fi= fileReadBinary( arguments.file );
				obj= createObject( "java", "org.jets3t.service.model.S3Object" ).init( arguments.key, fi );
			} else {
				var fi= createObject( "java", "java.io.File" ).init( arguments.file );
				obj= createObject( "java", "org.jets3t.service.model.S3Object" ).init( fi );
			}
			obj.setBucketName( arguments.bucket );
			obj.setKey( arguments.key );
			if ( arguments.type == "auto" ) {
				if ( structKeyExists( this.mimeTypes, listLast( arguments.key, "." ) ) ) {
					obj.setContentType( this.mimeTypes[ listLast( arguments.key, "." ) ] );
				}
			} else if ( len( arguments.type ) ) {
				obj.setContentType( arguments.type );
			}
			if ( len( arguments.disposition ) ) {
				obj.setContentDisposition( arguments.disposition );
			}
			if ( len( arguments.encoding ) ) {
				obj.setContentEncoding( arguments.encoding );
			}
			if ( listFindNoCase( "REDUCED_REDUNDANCY,REDUCED,R", arguments.storage ) ) {
				obj.setStorageClass( "REDUCED_REDUNDANCY" );
			} else if ( listFindNoCase( "STANDARD_IA,IA", arguments.storage ) ) {
				obj.setStorageClass( "STANDARD_IA" );
			}
			if ( arguments.acl == "public-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ );
			} else if ( arguments.acl == "public-read-write" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ_WRITE );
			} else if ( arguments.acl == "auth-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_AUTHENTICATED_READ  );
			} else {
				// private 
				obj.setAcl( this.aclObj.REST_CANNED_PRIVATE );
			}
			if ( arguments.maxAge > 0 ) {
				obj.addMetadata( "Cache-Control", "max-age=#arguments.maxAge#" );
			}
			if ( len( arguments.expires ) && isDate( arguments.expires ) ) {
				obj.addMetadata( "Expires", "#dateFormat( arguments.expires, 'ddd, dd mmm yyyy' )# #timeFormat( arguments.expires, 'H:MM:SS' )# GMT" );
			}
			for ( item in arguments.metaData ) {
				obj.addMetadata( item, arguments.metaData[ item ] );
			}
			this.s3.putObject( arguments.bucket, obj );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Puts an query of objects into a bucket.
	 */
	function putFileObjects(
		required string bucket
	,	required query query
	,	numeric threads= 1
	,	string acl= "private"
	,	numeric maxAge= 0
	,	string expires= ""
	,	string md5= "auto"
	,	struct metaData= {}
	,	string storage= ""
	) {
		var out= { success= true };

		queryEach( arguments.query, function( r ) {
			var out= this.putFileObject(
				bucket= r.bucket
			,	key= r.storageKey
			,	file= r.filename
			,	acl= r.acl
			,	maxAge= r.maxAge
			,	expires= r.expires
			,	metaData= r.metaData
			,	type= "auto"
			,	md5= r.md5
			);
			out[ r.storageKey ]= out;
			if( !out.success ) {
				out.success= false;
			}
		}, ( arguments.threads > 1 ), arguments.threads );
		return out;
	}

	/**
	 * @description Puts an object into a bucket.
	 */
	function putObject(
		required string bucket
	,	required string key
	,	required content
	,	string type= "auto"
	,	string disposition= ""
	,	string encoding= ""
	,	string acl= "private"
	,	numeric maxAge= 0
	,	string expires= ""
	,	string md5= ""
	,	struct metaData= {}
	,	string storage= ""
	) {
		var obj= 0;
		var item= "";
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "PUT [#arguments.bucket#][#arguments.key#]= #len( arguments.content )#/bytes" );
		try {
			obj= createObject( "java", "org.jets3t.service.model.S3Object" ).init( arguments.key, arguments.content );
			obj.setBucketName( arguments.bucket );
			if ( arguments.type == "auto" ) {
				if ( structKeyExists( this.mimeTypes, listLast( arguments.key, "." ) ) ) {
					obj.setContentType( this.mimeTypes[ listLast( arguments.key, "." ) ] );
				}
			} else if ( len( arguments.type ) ) {
				obj.setContentType( arguments.type );
			}
			if ( len( arguments.disposition ) ) {
				obj.setContentDisposition( arguments.disposition );
			}
			if ( len( arguments.encoding ) ) {
				obj.setContentEncoding( arguments.encoding );
			}
			if ( listFindNoCase( "REDUCED_REDUNDANCY,REDUCED,R", arguments.storage ) ) {
				obj.setStorageClass( "REDUCED_REDUNDANCY" );
			} else if ( listFindNoCase( "STANDARD_IA,IA", arguments.storage ) ) {
				obj.setStorageClass( "STANDARD_IA" );
			}
			if ( arguments.acl == "public-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ );
			} else if ( arguments.acl == "public-read-write" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ_WRITE );
			} else if ( arguments.acl == "auth-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_AUTHENTICATED_READ  );
			} else {
				// private 
				obj.setAcl( this.aclObj.REST_CANNED_PRIVATE );
			}
			if ( arguments.maxAge > 0 ) {
				obj.addMetadata( "Cache-Control", "max-age=#arguments.maxAge#" );
			}
			if ( len( arguments.expires ) && isDate( arguments.expires ) ) {
				obj.addMetadata( "Expires", "#dateFormat( arguments.expires, 'ddd, dd mmm yyyy' )# #timeFormat( arguments.expires, 'H:MM:SS' )# GMT" );
			}
			for ( item in arguments.metaData ) {
				obj.addMetadata( item, arguments.metaData[ item ] );
			}
			this.s3.putObject( arguments.bucket, obj );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Get an object.
	 */
	function getObject( required string bucket, required string key ) {
		var obj= 0;
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "GET [#arguments.bucket#][#arguments.key#]" );
		try {
			obj= this.s3.getObject( arguments.bucket, arguments.key );
			out.content= this.utils.readInputStreamToString( obj.getDataInputStream(), "UTF-8" );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Get an object as a file.
	 */
	function getFile( required string bucket, required string key, string file= "" ) {
		var obj= 0;
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "GET [#arguments.bucket#][#arguments.key#]= #arguments.file#" );
		try {
			obj= this.s3.getObject( arguments.bucket, arguments.key );
			var utils= createObject( "java", "org.apache.commons.io.IOUtils" ).init();
			var data= utils.toByteArray( obj.getDataInputStream() );
			if ( !obj.verifyData( data ) ) {
				throw( message="Downloaded data does not match hash." );
			}
			fileWrite( arguments.file, data );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		if ( !out.success && fileExists( arguments.file ) ) {
			try {
				cffile( file=arguments.file, action="delete" );
			} catch (any cfcatch) {
			}
		}
		return out;
	}
	
	/**
	 * @description Download an object.
	 */
	function getObjectInfo( required string bucket, required string key ) {
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			out.info= this.s3.getObjectDetails( arguments.bucket, arguments.key );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Deletes an object.
	 */
	function deleteObject( required string bucket, required string key ) {
		var out= {
			success= false
		,	errorDetail= ""
		};
		this.debugLog( "S3 DELETE [#arguments.bucket#][#arguments.key#]" );
		try {
			this.s3.deleteObject( arguments.bucket, arguments.key );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Copies an object.
	 */
	function copyObject(
		required string bucket
	,	required string key
	,	required string newBucket= arguments.bucket
	,	required string newKey
	,	struct metaData= {}
	,	string acl= "private"
	,	string storage= ""
	) {
		var obj= 0;
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			obj= this.s3.getObjectDetails( arguments.bucket, arguments.key );
			obj.setKey( arguments.newKey );
			obj.setBucketName( arguments.newBucket );
			if ( arguments.acl == "public-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ );
			} else if ( arguments.acl == "public-read-write" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ_WRITE );
			} else if ( arguments.acl == "auth-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_AUTHENTICATED_READ  );
			} else {
				// private 
				obj.setAcl( this.aclObj.REST_CANNED_PRIVATE );
			}
			if ( listFindNoCase( "REDUCED_REDUNDANCY,REDUCED,R", arguments.storage ) ) {
				obj.setStorageClass( "REDUCED_REDUNDANCY" );
			} else if ( listFindNoCase( "STANDARD_IA,IA", arguments.storage ) ) {
				obj.setStorageClass( "STANDARD_IA" );
			}
			for ( item in arguments.metaData ) {
				obj.addMetadata( item, arguments.metaData[ item ] );
			}
			var cmd= this.s3.copyObject( arguments.bucket, arguments.key, arguments.newBucket, obj, !structIsEmpty( arguments.metadata ) );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description 
	 */
	function updateObject(
		required string bucket
	,	required string key
	,	string type= "auto"
	,	string disposition= ""
	,	string encoding= ""
	,	string acl= "private"
	,	numeric maxAge= 0
	,	string expires= ""
	,	struct metaData= {}
	,	string storage= ""
	) {
		var obj= 0;
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			obj= this.s3.getObjectDetails( arguments.bucket, arguments.key );
			obj.setKey( arguments.newKey );
			obj.setBucketName( arguments.newBucket );
			if ( arguments.type == "auto" ) {
				if ( structKeyExists( this.mimeTypes, listLast( arguments.key, "." ) ) ) {
					obj.setContentType( this.mimeTypes[ listLast( arguments.key, "." ) ] );
				}
			} else if ( len( arguments.type ) ) {
				obj.setContentType( arguments.type );
			}
			if ( len( arguments.disposition ) ) {
				obj.setContentDisposition( arguments.disposition );
			}
			if ( len( arguments.encoding ) ) {
				obj.setContentEncoding( arguments.encoding );
			}
			if ( listFindNoCase( "REDUCED_REDUNDANCY,REDUCED,R", arguments.storage ) ) {
				obj.setStorageClass( "REDUCED_REDUNDANCY" );
			} else if ( listFindNoCase( "STANDARD_IA,IA", arguments.storage ) ) {
				obj.setStorageClass( "STANDARD_IA" );
			}
			if ( arguments.acl == "public-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ );
			} else if ( arguments.acl == "public-read-write" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ_WRITE );
			} else if ( arguments.acl == "auth-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_AUTHENTICATED_READ  );
			} else { // private 
				obj.setAcl( this.aclObj.REST_CANNED_PRIVATE );
			}
			if ( arguments.maxAge > 0 ) {
				obj.addMetadata( "Cache-Control", "max-age=#arguments.maxAge#" );
			}
			if ( len( arguments.expires ) && isDate( arguments.expires ) ) {
				obj.addMetadata( "Expires", "#dateFormat( arguments.expires, 'ddd, dd mmm yyyy' )# #timeFormat( arguments.expires, 'H:MM:SS' )# GMT" );
			}
			for ( item in arguments.metaData ) {
				obj.addMetadata( item, arguments.metaData[ item ] );
			}
			var cmd= this.s3.updateObjectMetadata( arguments.bucket, obj );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

	/**
	 * @description Renames an object by copying then deleting original.
	 */
	function renameObject(
		required string bucket
	,	required string key
	,	required string newBucket= arguments.bucket
	,	required string newKey
	,	string acl= "private"
	,	string storage= ""
	) {
		var obj= 0;
		var out= {
			success= false
		,	errorDetail= ""
		};
		try {
			obj= this.s3.getObjectDetails( arguments.bucket, arguments.key );
			obj.setKey( arguments.newKey );
			obj.setBucketName( arguments.newBucket );
			if ( arguments.acl == "public-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ );
			} else if ( arguments.acl == "public-read-write" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PUBLIC_READ_WRITE );
			} else if ( arguments.acl == "auth-read" ) {
				obj.setAcl( this.aclObj.REST_CANNED_AUTHENTICATED_READ  );
			} else if ( arguments.acl == "private" ) {
				obj.setAcl( this.aclObj.REST_CANNED_PRIVATE );
			}
			if ( listFindNoCase( "REDUCED_REDUNDANCY,REDUCED,R", arguments.storage ) ) {
				obj.setStorageClass( "REDUCED_REDUNDANCY" );
			} else if ( listFindNoCase( "STANDARD_IA,IA", arguments.storage ) ) {
				obj.setStorageClass( "STANDARD_IA" );
			}
			var cmd= this.s3.moveObject( arguments.bucket, arguments.key, arguments.newBucket, obj, false );
			out.success= true;
		} catch (org.jets3t.service.S3ServiceException cfcatch) {
			out.success= false;
			if ( structKeyExists( cfcatch, "getErrorMessage" ) ) {
				out.errorDetail= cfcatch.getErrorMessage() & " code[" & cfcatch.getResponseCode() & "]";
			} else {
				out.errorDetail= cfcatch.message;
			}
			out.exception= cfcatch;
		} catch (any cfcatch) {
			out.success= false;
			out.errorDetail= cfcatch.message;
			out.exception= cfcatch;
		}
		return out;
	}

}
