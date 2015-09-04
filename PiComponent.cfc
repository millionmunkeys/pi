<cfcomponent displayname="PI Component" hint="An object that implements the Property-Invocation (PI) programming standard.">
	<!--- 
			A few notes about properties:
			1) ColdFusion Structs capitalize all struct keys.  In order to retain the proper case
			of a key, we track it in the properties array, which preserves the case.  However,
			when doing lookups we always do case-insensitive lookups, keeping in sync with 
			ColdFusion expectations.  So you may be asking why do we care about case sensitivy 
			of keys if we're not doing case-sensitive lookups?  The answer is because if we 
			wish to convert a structure to a case-sensitive language like Javascript, we need 
			to know the original case of the arguments.
			2) ColdFusion structs also don't track the order in which items are added.  Using
			an array of properties allows us to have one object that can act as both an array
			and an associative array (i.e. "struct") at the same time.
			3) I tried managing the information through a query, but since the values may be
			objects themselves, and not just simple values, that approach appears to be a dead end.
	--->
	<cfset UUID = "" /><!--- This is for guaranteeing object uniqueness.  See getUUID function. --->
	<cfset uid = 0 /><!--- This is for unique property names. --->
	<!--- The following two items are temporarily public for debugging purposes. --->
	<cfset this.properties = ArrayNew(1) /><!--- properties are ordered, but indexed. --->
	<cfset values = StructNew() />
	<cfset this.length = ArrayLen(this.properties) />
	<cfset this.listeners = StructNew() />
	<cfset this.filters = StructNew() />
	<cfset this.globalListeners = ArrayNew(1) />
	<cfset this.globalFilters = ArrayNew(1) />
	
	<!--- PRIVATE STORAGE --->
	
	<!--- Special data storage that is only available internally to objects that extend the PiComponent. --->
	<cffunction name="getPrivate" access="private" output="no">
		<cfif not StructKeyExists(Variables,"private")>
			<!--- We instantiate inside the get function.  Otherwise you get an endless loop condition on instantiation. --->
			<cfset private = CreateObject("component","PiComponent") />
		</cfif>
		<cfreturn private />
	</cffunction>
		
	<!--- Special data storage that is only available to Pi Objects and others objects in the same folder. ---> 
	<cffunction name="getProtected" access="package" output="no">
		<cfif not StructKeyExists(Variables,"protected")>
			<!--- We instantiate inside the get function.  Otherwise you get an endless loop condition on instantiation. --->
			<cfset protected = CreateObject("component","PiComponent") />
		</cfif>
		<cfreturn protected />
	</cffunction>
		
	<!--- UNIQUENESS --->
	
	<!--- The following function exists because ColdFusion cannot compare complex data types, but if each component has a UUID, then comparison is easy. --->
	<cffunction name="getUUID" output="no">
		<cfif not Len(UUID)>
			<cfset UUID = CreateUUID() />
		</cfif>
		<cfreturn UUID />
	</cffunction>
	
	<!--- INSTANTIATION --->
	
	<cffunction name="new" returntype="PiComponent" hint="A shortcut function that returns a new instance of any child class that extends this component." output="no">
		<cfset var my = StructNew() />
		<cfset my.path = GetCurrentTemplatePath() />
		<cfset my.path = Right(my.path,Len(my.path)-Len(ExpandPath("/MillionMunkeys"))) /><!--- Convert to CF Path --->
		<cfset my.path = Left(my.path,Len(my.path)-4) /><!--- Remove ".cfc" extension --->
		<cfset my.newObject = CreateObject("component", "MillionMunkeys.#Replace(my.path,'\/','.','all')#" ) />
		<cfif StructKeyExists(Arguments,"1")>
			<cfset my.newObject.add(ArgumentCollection=Arguments) />
		<cfelse>
			<cfset my.newObject.set(ArgumentCollection=Arguments) />
		</cfif>
		<cfreturn my.newObject />
	</cffunction>
	
	<cffunction name="newMunkey" returntype="PiComponent" hint="A shortcut function for any child of the PiComponent that returns a new instance of the base PiComponent class, and not the child class.  To get a new instance of the child class use the  'new' function.  WARNING: This function should never be overridden by a child class!" output="no">
		<cfset var my = StructNew() />
		<cfset my.newObject = CreateObject("component","PiComponent") />
		<cfif StructCount(Arguments)>
			<cfif StructKeyExists(Arguments,"1")>
				<cfset my.newObject.add(ArgumentCollection=Arguments) />
			<cfelse>
				<cfset my.newObject.set(ArgumentCollection=Arguments) />
			</cfif>
		</cfif>
		<cfreturn my.newObject />
	</cffunction>
	
	<!--- INDEXES --->
	
	<cffunction name="getLength" returntype="numeric" hint="Returns the total number of properties of this object." output="no">
		<cfreturn ArrayLen(this.properties) />
	</cffunction>
	
	<cffunction name="getPropertyList" returntype="string" hint="Returns a list of all of the properties of this object." output="no">
		<cfargument name="propertyName" default="" />
		<cfset var my = StructNew() />
		<cfif Len(Arguments.propertyName)>
			<cfloop from="1" to="#ArrayLen(this.properties)#" index="my.index">
				<cfset my.item = this.get(my.index) />
				<cfif isObject(my.item)>
					<cfset my.propList = ListAppend(my.propList,my.item.get(Arguments.propertyName)) />
				<cfelseif isStruct(my.item)>
					<cfset my.propList = ListAppend(my.propList,my.item[Arguments.propertyName]) />
				<cfelse>
					<cfset my.propList = ListAppend(my.propList,"") />
				</cfif>
			</cfloop>
		<cfelse>
			<cfset my.propList = ArrayToList(this.properties) />
		</cfif>
		<cfreturn my.propList />
	</cffunction>
	
	<cffunction name="getProperty" returntype="string" hint="Finds the property name associated with a given index." output="no">
		<cfargument name="index" required="yes" />
		<cfif not isNumeric(Arguments.index)>
			<cfreturn Trim(Arguments.index) />
		<cfelseif Arguments.index gt 0 and Arguments.index lte getLength()>
			<cfreturn this.properties[Arguments.index] />
		<cfelse>
			<cfreturn "" />
		</cfif>
	</cffunction>
	
	<cffunction name="getIndex" returntype="numeric" hint="Converts property names to their numeric positions in the Array." output="no">
		<cfargument name="propertyName" />
		<cfif not isNumeric(Arguments.propertyName)>
			<cfset Arguments.propertyName = ListFindNoCase(getPropertyList(),Arguments.propertyName) />
		<cfelseif Arguments.propertyName gt ArrayLen(this.properties)>
			<cfreturn 0 />
		</cfif>
		<cfreturn Arguments.propertyName />
	</cffunction>
	
	<!--- SET --->
	
	<cffunction name="set" hint="A function for direct assignment of properties, singly or in bulk."><!--- WARNING: Allow output --->
		<cfset var my = StructNew() />
		<cfset my.singleSet = false />
		<!--- Check Arguments --->
		<cfif StructCount(Arguments) neq 2 and StructKeyExists(Arguments,"1")>
			<!--- EXIT: Either the user has a bug, or they are really looking for the append function.  Let them determine which it is. --->
			<cfthrow message="Incorrect Number of Arguments" detail="The 'Set' function is expecting either two unnamed arguments, e.g. set(""name"",""PiComponent""), or a collection of named arguments, e.g. set(name=""PiComponent"",type=""ColdFusion"",copyright=""MillionMunkeys.net"").  You may want to use the 'Append' function instead for adding multiple unnamed values, e.g. append(""ColdFusion"",""Javascript"",""PHP"")." />
		</cfif>
<!---<cfdump var="#Arguments#" label="PiComponent set function arguments">--->
		<cftry>
			<!--- The following is used for case-sensitive assignments and numeric assignments. --->
			<cfif StructCount(Arguments) eq 2 and StructKeyExists(Arguments,"1") and StructKeyExists(Arguments,"2")>
				<cfset my.arg = Arguments.1 />
				<cfset my.newValue = Arguments.2 />
				<cfset my.singleSet = true />
				<cfset StructClear(Arguments) />
				<cfset Arguments[my.arg]=my.newValue />
<!---<cfdump var="#Arguments#" label="Arguments.1 translated to Arguments[my.arg]">--->
			</cfif>
			<!--- The following is used for bulk case-insensitive assignments. --->
			<cfset my.count = 0 />
			<cfloop list="#StructKeyList(Arguments)#" index="my.arg">
				<cfset my.count = my.count + 1 /><!--- There is a bug in StructCount after using StructClear, so doing my own count. --->
				<cfset my.index = my.arg />
				<cfif isNumeric(my.arg)>
					<!--- my.arg will only ever be numeric if Arguments.1 was a numeric index above. --->
					<cfset my.arg = getProperty(my.arg) />
				</cfif>
				<cfif StructKeyExists(values,my.arg)>
					<cfset my.oldValue=values[my.arg] />
				<cfelse>
					<cfset my.oldValue="" />
				</cfif>
				<cfif getIndex(my.index) eq 0>
					<cfset uid = uid + 1 />
					<cfset ArrayAppend(this.properties,my.arg) />
					<cfset this.length = ArrayLen(this.properties) />
				</cfif>
				<cfset my.newValue=Arguments[my.arg] />
				<cfset values[my.arg]=my.newValue />
				<cfif StructKeyExists(this.listeners,my.arg)>
					<!--- Transfer to local scope because if a listener removes another listener, we'll get an error. --->
					<cfset my.listeners = this.listeners[my.arg] />
					<cfloop from="1" to="#ArrayLen(my.listeners)#" index="my.index">
						<cfinvoke component="#my.listeners[my.index].object#" method="#my.listeners[my.index].methodname#" returnvariable="my.result" >
							<cfinvokeargument name="object" value="#this#" />
							<cfinvokeargument name="property" value="#my.index#" /><!--- We use my.index because it could be string or numeric. --->
							<cfinvokeargument name="oldValue" value="#my.oldValue#" />
							<cfinvokeargument name="newValue" value="#my.newValue#" />
						</cfinvoke>
						<cfif StructKeyExists(my,"result")>
							<!--- In case the listeners have changed the value, add it to the struct again. --->
							<cfset my.newValue = my.result />
							<cfset values[my.arg]=my.newValue />
						</cfif>
					</cfloop>
				</cfif>
				<cfset my.listeners = this.globalListeners />
				<cfloop from="1" to="#ArrayLen(my.listeners)#" index="my.index">
					<cfinvoke component="#my.listeners[my.index].object#" method="#my.listeners[my.index].methodname#" returnvariable="my.result">
						<cfinvokeargument name="object" value="#this#" />
						<cfinvokeargument name="property" value="#my.index#" /><!--- We use my.index because it could be string or numeric. --->
						<cfinvokeargument name="oldValue" value="#my.oldValue#" />
						<cfinvokeargument name="newValue" value="#my.newValue#" />
					</cfinvoke>
					<cfif StructKeyExists(my,"result")>
						<!--- In case the listeners have changed the value, add it to the struct again. --->
						<cfset my.newValue = my.result />
						<cfset values[my.arg]=my.newValue />
					</cfif>
				</cfloop>
			</cfloop>
			<cfset this.length = ArrayLen(this.properties) />
			<!--- There is a bug in StructCount after using StructClear. --->
			<cfif my.singleSet>
				<!--- If only one value, return it. --->
				<cfreturn get(my.arg) /> <!--- Use get function so that the filters are fired. --->
			<cfelse>
				<cfreturn this /> <!--- Allow chaining --->
			</cfif>
			<cfcatch>
				<!---
				<cfdump var="#Arguments#">
				<cfdump var="#my.arg#">
				<cfdump var="#my.index#">
				<cfdump var="#ArrayLen(this.globalListeners)#">
				<cfdump var="#cfcatch#">
				<cfabort>
				--->
				<cfrethrow />
			</cfcatch>
		</cftry>
	</cffunction>
	
	<!--- I have a dilemma: The proper name for this function is "insert", but that is a reserved word in ColdFusion. --->
	<cffunction name="insertAt" hint="Insert values in the middle of the PiComponent's Array."><!--- WARNING: Allow output --->
		<cfargument name="i" required="yes" />
		<cfset var my = StructNew() />
		<cfset my.args = StructNew() />
		<cfset my.index=getIndex(Arguments.i) />
		<cfloop from="2" to="#StructCount(Arguments)#" index="my.arg">
			<cfif not isNumeric(my.arg)>
				<cfthrow message="Named Arguments Not Allowed" detail="The 'insertAt' function is expecting unnamed arguments starting with the index of where to insert the values, e.g. insertAt(5,""dog"",""cat"",""mouse"").  You may want to use the 'Set' function instead for adding named values, e.g. set(name=""PiComponent"",type=""ColdFusion"",copyright=""MillionMunkeys.net"")." />
			</cfif>
			<!--- When doing an insertAt or append, we use UIDs --->
			<cfset uid = uid + 1 />
			<cfif my.index>
				<cfset ArrayInsertAt(this.properties,my.index,'item#uid#') />
			<cfelse>
				<cfset ArrayAppend(this.properties,'item#uid#') />
			</cfif>
			<cfset my.args['item#uid#'] = Arguments[my.arg] />
		</cfloop>
		<cfset this.length = ArrayLen(this.properties) />
		<cfreturn set(ArgumentCollection=my.args) /><!--- Allow chaining --->
	</cffunction>
	
	<cffunction name="add" hint="Adds values to the end of a PiComponent as an Array."><!--- WARNING: Allow output --->
		<cfset var my = StructNew() />
		<cfset my.args = StructNew() />
		<cfloop from="1" to="#StructCount(Arguments)#" index="my.prop">
			<cfif not isNumeric(my.prop)>
				<cfthrow message="Named Arguments Not Allowed" detail="The 'Add' function is expecting unnamed arguments, e.g. append(""dog"",""cat"",""mouse"").  You may want to use the 'Set' function instead for adding named values, e.g. set(name=""PiComponent"",type=""ColdFusion"",copyright=""MillionMunkeys.net"")." />
			</cfif>
			<!--- When doing an add or append, we use UIDs --->
			<cfset uid = uid + 1 />
			<cfset ArrayAppend(this.properties,'item#uid#') />
			<cfset this.length = ArrayLen(this.properties) />
			<cfset my.args['item#uid#'] = Arguments[my.prop] />
		</cfloop>
		<cfreturn set(ArgumentCollection=my.args) /><!--- Allow chaining --->
	</cffunction>
	<cffunction name="append" hint="An alias for the add function."><!--- WARNING: Allow output --->
		<cfreturn add(ArgumentCollection=Arguments) />
	</cffunction>
		
	<cffunction name="remove" hint="Removes the specified property from the object."><!--- WARNING: Allow output --->
		<cfset var my = StructNew() />
		<cfset my.args = StructNew() />
		<cfloop list="#StructKeyList(Arguments)#" index="my.arg">
			<cfset my.prop = getProperty(Arguments[my.arg]) />
			<cfif StructKeyExists(values,my.prop)>
				<cfset my.args[my.prop] = "" />
			</cfif>
		</cfloop>
		<cfset set(ArgumentCollection=my.args) /><!--- Let set call the listeners --->
		<cfloop list="#StructKeyList(my.args)#" index="my.prop">
			<cfset my.index = getIndex(my.prop) />
			<cfif not Len(values[my.prop])>
				<cfset StructDelete(values,my.prop,false) />
				<cfif my.index>
					<cfset ArrayDeleteAt(this.properties,my.index) />
				</cfif>
			</cfif>
		</cfloop>
		<cfset this.length = ArrayLen(this.properties) />
		<cfreturn this /><!--- Allow chaining --->
	</cffunction>
	<cffunction name="delete" hint="An alias for the delete function."><!--- WARNING: Allow output --->
		<cfreturn remove(ArgumentCollection=Arguments) />
	</cffunction>
	
	<cffunction name="removeAll" hint="WARNING: The point of this function is to clean out a PiComponent, so it will ignore any listeners that restore values, and delete them anyway!!!">
		<cfset var my = StructNew() />
		<cfset my.args = StructNew() />
		<cfloop list="#StructKeyList(values)#" index="my.prop">
			<cfset my.args[my.prop] = "" />
		</cfloop>
		<cfset set(ArgumentCollection=my.args) /><!--- Fire listeners for deletes --->
		<cfset StructClear(values) />
		<cfset ArrayClear(this.properties) />
		<cfset this.length = ArrayLen(this.properties) />
		<cfreturn this /><!--- Allow chaining --->
	</cffunction>
	<cffunction name="deleteAll">
		<cfreturn removeAll() />
	</cffunction>
	
	<cffunction name="move" hint="A special class of function that doesn't change the value of the property, but just reorders it, according to Array syntax.">
		<cfargument name="oldIndex" />
		<cfargument name="newIndex" />
		<cfset var my = StructNew() />
		<cfset my.length = getLength() />
		<!--- Allows the use of negative indexes. --->
		<!--- Make sure that if property names are used, they are converted into numerical indexes. --->
		<cfif not isNumeric(Arguments.oldIndex)>
			<cfset Arguments.oldIndex = this.getIndex(Arguments.oldIndex) />
			<cfif Arguments.oldIndex lte 0>
				<cfthrow message="index does not exist" />
			</cfif>
		</cfif>
		<cfif Abs(Arguments.oldIndex) gt my.length>
			<cfthrow message="index does not exist" />
		</cfif>
		<!--- Make sure that if newIndex is a property it is converted into a numerical index. --->
		<cfif not isNumeric(Arguments.newIndex)>
			<cfset Arguments.newIndex = this.getIndex(Arguments.newIndex) />
			<cfif Arguments.newIndex lte 0>
				<cfset Arguments.newIndex = my.length /><!--- Treat like an add operation --->
			</cfif>
		</cfif>
		<!--- Convert Negative numbers in positive equivalents. --->
		<cfif Arguments.oldIndex lte 0>
			<cfset Arguments.oldIndex = my.length + Arguments.oldIndex />
		</cfif>
		<cfif Arguments.newIndex lte 0>
			<cfset Arguments.newIndex = my.length + Arguments.newIndex />
		</cfif>
		<!--- In case the designer is passing variables that just happend to evaluate to the same number, don't waste time on fake moves. --->
		<cfif Arguments.oldIndex neq Arguments.newIndex>
			<cfset my.prop = this.properties[Arguments.oldIndex] />
			<cfset ArrayDeleteAt(this.properties,Arguments.oldIndex) />
			<cfif Arguments.newIndex gte my.length>
				<cfset ArrayAppend(this.properties,my.prop) />
			<cfelse>
				<cfset ArrayInsertAt(this.properties,Arguments.newIndex,my.prop) />
			</cfif>
		</cfif>
		<cfreturn this /><!--- Allow chaining --->
	</cffunction>
	
	<!--- GET --->
	
	<cffunction name="get" hint="Returns the value of a property, or the empty string if not found." output="no">
		<cfargument name="prop" required="yes" />
		<!--- WARNING: Don't allow output, or else it will append whitespace and character returns to all output, screwing up your HTML. --->
		<!--- CAUTION: There might be an issue, which I can't reproduce now, where setting output="no" prevents the display of content included during a get or set operation. --->
		<cfset var my = StructNew() />
		<cfset my.result="" />
		<cfset Arguments.prop = getProperty(Arguments.prop) />
		<cfif StructKeyExists(values,Arguments.prop)>
			<cfset my.result = values[Arguments.prop] />
		</cfif>
		<!--- Transfer to local scope because if a filter removes another filter, we'll get an error. --->
		<cfif StructKeyExists(this.filters,Arguments.prop)>
			<cfset my.filters = this.filters[Arguments.prop] />
			<cfloop from="1" to="#ArrayLen(my.filters)#" index="my.index">
				<cfinvoke component="#my.filters[my.index].object#" method="#my.filters[my.index].methodname#" returnvariable="my.returnVariable">
					<cfinvokeargument name="object" value="#this#" />
					<cfinvokeargument name="property" value="#Arguments.prop#" />
					<cfinvokeargument name="value" value="#my.result#" />
				</cfinvoke>
				<cfif StructKeyExists(my,"returnVariable")>
					<cfset my.result = my.returnVariable />
				</cfif>
			</cfloop>
		</cfif>
		<cfset my.filters = this.globalFilters />
		<cfloop from="1" to="#ArrayLen(my.filters)#" index="my.index">
			<cfinvoke component="#my.filters[my.index].object#" method="#my.filters[my.index].methodname#" returnvariable="my.returnVariable">
				<cfinvokeargument name="object" value="#this#" />
				<cfinvokeargument name="property" value="#Arguments.prop#" />
				<cfinvokeargument name="value" value="#my.result#" />
			</cfinvoke>
			<cfif StructKeyExists(my,"returnVariable")>
				<cfset my.result = my.returnVariable />
			</cfif>
		</cfloop>
		<cfreturn my.result />
	</cffunction>
	
	<cffunction name="exists" returntype="boolean" hint="Indicates whether or not the specified property exists." output="no">
		<cfargument name="prop" required="yes" />
		<cfset Arguments.prop = getProperty(Arguments.prop) />
		<cfif Len(Arguments.prop) and getIndex(Arguments.prop) gt 0>
			<cfreturn true />
		<cfelse>
			<cfreturn false />
		</cfif>
	</cffunction>
	
	<!--- FUNCTIONS --->
	
	<cffunction name="addFunction" hint="The core function for adding filters and listeners." output="no" access="private">
		<cfargument name="type" required="yes" />
		<cfargument name="action" required="yes" />
		<cfargument name="property" default="" />
		<cfargument name="object" />
		<cfargument name="methodname" />
		<cfargument name="applyToExisting" />
		<cfset var my = StructNew() />
		<cfset my.alreadyExists = false />
		<cfset my.type = Arguments.type />
		<cfset my.action = Arguments.action />
		<cfset StructDelete(Arguments,"type") />
		<cfset StructDelete(Arguments,"action") />
		<!--- You can add a global listener by just supplying an object and a method. --->
		<cfif not StructKeyExists(Arguments,'methodname') or isBoolean(Arguments.methodname)>
			<cfif not StructKeyExists(Arguments,"methodname")>
				<cfset Arguments.methodname = Arguments.object />
				<cfset StructDelete(Arguments,"object") />
			<cfelseif isBoolean(Arguments.methodname)>
				<cfset Arguments.applyToExisting = Arguments.methodname />
				<cfset Arguments.methodname = Arguments.object />
				<cfset StructDelete(Arguments,"object") />
			</cfif>
			<cfif not StructKeyExists(Arguments,"object") and isObject(Arguments.property)>
				<cfset Arguments.object = Arguments.property />
				<cfset Arguments.property = [""] />
			</cfif>
		</cfif>
		<!--- Allow for assigning to multiple properties at once.
			Multiple named properties can be supplied through a list of names, e.g. "prop1,prop3,prop5", or an array of names, e.g. ["prop1","prop3","prop4"].
			Multiple indexes must be supplied through an array of indexes, e.g. [1,3,5], or else they will be assumed to be names, e.g. "1,3,5" == ["1","3","5"].
			You can mix named and numbered properties through using an array, e.g. ["prop1",3,"prop5"]. --->
		<cfif not isArray(Arguments.property)>
			<cfset Arguments.property = ListToArray(Arguments.property) />
		</cfif>
		<cfif ArrayLen(Arguments.property) eq 0>
			<cfset Arguments.property = [""] />
		</cfif>
		<cfparam name="Arguments.applyToExisting" default="true" />
		<cfif not isBoolean(Arguments.applyToExisting)>
			<cfset Arguments.applyToExisting = true />
		</cfif>
		<!--- Check the types of the arguments. --->
		<cfif not isObject(Arguments.object)>
<!---<cfdump var="#Arguments.object#">--->
<!---<cfabort>--->
			<cfthrow message="Invalid parameter type." detail="The 'object' parameter does not evaluate to a valid object." />
		</cfif>
		<cfparam name="Arguments.methodname" type="string" />
		<!--- CAUTION: We need to use an array for this loop because if it's the empty string, looping over a list never executes. --->
		<cfloop from="1" to="#ArrayLen(Arguments.property)#" index="my.i">
			<cfset my.prop = Arguments.property[my.i] />
			<!--- Global or Property Function? --->
			<cfif Len(my.prop) and isNumeric(my.prop)>
				<!--- Property Functions --->
				<cfset my.prop = getProperty(my.prop) />
			</cfif>
			<!--- Add/Remove Function --->
			<!--- CAUTION: Arrays are not assigned by pointer, meaning that if you assign array to another variable and then update that array, those updates will not persist back to the original array!  So we will have to do a little duplication of code here. --->
			<cfswitch expression="#my.action#">
				<cfcase value="add">
					<cfif Len(my.prop)>
						<cfif my.type eq "filter">
							<cfparam name="this.filters[my.prop]" default="#ArrayNew(1)#" />
							<cfloop from="#ArrayLen(this.filters[my.prop])#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.filters[my.prop][my.index].methodname eq Arguments.methodname and this.filters[my.prop][my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset my.alreadyExists = true />
								</cfif>
							</cfloop>
							<cfif not my.alreadyExists>
								<cfset ArrayAppend(this.filters[my.prop],Arguments) />
							</cfif>
						<cfelseif my.type eq "listener">
							<cfparam name="this.listeners[my.prop]" default="#ArrayNew(1)#" />
							<cfloop from="#ArrayLen(this.listeners[my.prop])#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.listeners[my.prop][my.index].methodname eq Arguments.methodname and this.listeners[my.prop][my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset my.alreadyExists = true />
								</cfif>
							</cfloop>
							<cfif not my.alreadyExists>
								<cfset ArrayAppend(this.listeners[my.prop],Arguments) />
								<cfif Arguments.applyToExisting>
									<cfif StructKeyExists(values,my.prop)>
										<cfinvoke component="#Arguments.object#" method="#Arguments.methodname#" returnvariable="my.result">
											<cfinvokeargument name="object" value="#this#" />
											<cfinvokeargument name="property" value="#my.prop#" />
											<cfinvokeargument name="oldValue" value="" />
											<cfinvokeargument name="newValue" value="#values[my.prop]#" />
										</cfinvoke>
										<cfif StructKeyExists(my,"result")>
											<cfset values[my.prop] = my.result />
										</cfif>
									</cfif>
								</cfif>
							</cfif>
						</cfif>
					<cfelse>
						<!--- CAUTION: Can't delete Arguments.property anymore because we still need the array. --->
						<!--- <cfset StructDelete(Arguments,"property") /> --->
						<cfif my.type eq "filter">
							<cfloop from="#ArrayLen(this.globalFilters)#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.globalFilters[my.index].methodname eq Arguments.methodname and this.globalFilters[my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset my.alreadyExists = true />
								</cfif>
							</cfloop>
							<cfif not my.alreadyExists>
								<cfset ArrayAppend(this.globalFilters,Arguments) />
							</cfif>
						<cfelseif my.type eq "listener">
							<cfloop from="#ArrayLen(this.globalListeners)#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.globalListeners[my.index].methodname eq Arguments.methodname and this.globalListeners[my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset my.alreadyExists = true />
								</cfif>
							</cfloop>
							<cfif not my.alreadyExists>
								<cfset ArrayAppend(this.globalListeners,Arguments) />
								<cfif Arguments.applyToExisting>
									<cfloop from="1" to="#ArrayLen(this.properties)#" index="my.index">
										<cfif StructKeyExists(values,this.properties[my.index])>
											<cfinvoke component="#Arguments.object#" method="#Arguments.methodname#" returnvariable="my.result">
												<cfinvokeargument name="object" value="#this#" />
												<cfinvokeargument name="property" value="#this.properties[my.index]#" />
												<cfinvokeargument name="oldValue" value="" />
												<cfinvokeargument name="newValue" value="#values[this.properties[my.index]]#" />
											</cfinvoke>
											<cfif StructKeyExists(my,"result")>
												<cfset values[this.properties[my.index]] = my.result />
											</cfif>
										</cfif>
									</cfloop>
								</cfif>
							</cfif>
						</cfif>
					</cfif>
				</cfcase>
				<cfcase value="remove">
					<!--- Find the given function. --->
					<cfif Len(my.prop)>
						<cfif my.type eq "filter">
							<cfif StructKeyExists(this.filters,my.prop)>
								<cfloop from="#ArrayLen(this.filters[my.prop])#" to="1" step="-1" index="my.index">
									<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
									<cfif this.filters[my.prop][my.index].methodname eq Arguments.methodname and this.filters[my.prop][my.index].object.getUUID() eq Arguments.object.getUUID()>
										<cfset ArrayDeleteAt(this.filters[my.prop],my.index) />
									</cfif>
								</cfloop>
							</cfif>
						<cfelseif my.type eq "listener">
							<cfif StructKeyExists(this.listeners,my.prop)>
								<cfloop from="#ArrayLen(this.listeners[my.prop])#" to="1" step="-1" index="my.index">
									<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
									<cfif this.listeners[my.prop][my.index].methodname eq Arguments.methodname and this.listeners[my.prop][my.index].object.getUUID() eq Arguments.object.getUUID()>
										<cfset ArrayDeleteAt(this.listeners[my.prop],my.index) />
									</cfif>
								</cfloop>
							</cfif>
						</cfif>
					<cfelse>
						<cfif my.type eq "filter">
							<cfloop from="#ArrayLen(this.globalFilters)#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.globalFilters[my.index].methodname eq Arguments.methodname and this.globalFilters[my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset ArrayDeleteAt(this.globalFilters,my.index) />
								</cfif>
							</cfloop>
						<cfelseif my.type eq "listener">
							<cfloop from="#ArrayLen(this.globalListeners)#" to="1" step="-1" index="my.index">
								<!--- ColdFusion can only compare simple values, so we're going to do our own object comparison. --->
								<cfif this.globalListeners[my.index].methodname eq Arguments.methodname and this.globalListeners[my.index].object.getUUID() eq Arguments.object.getUUID()>
									<cfset ArrayDeleteAt(this.globalListeners,my.index) />
								</cfif>
							</cfloop>
						</cfif>
					</cfif>
				</cfcase>
			</cfswitch>
		</cfloop>
	</cffunction>
	
	<cffunction name="addListener" hint="Adds a listener function to either the entire object as a whole, or a specific property within the object.  NOTE: You may add a listener to property even if the property doesn't exist yet.  It will be fired when the property is added to the object." output="no">
		<cfargument name="property" default="" />
		<cfargument name="object" />
		<cfargument name="methodname" />
		<cfargument name="applyToExisting" />
		<cfset Arguments.type="listener" />
		<cfset Arguments.action="add" />
<!---<cfdump var="#Arguments#" label="addListener arguments">--->
		<cfreturn addFunction(ArgumentCollection=Arguments) />
	</cffunction>
	<cffunction name="removeListener" hint="Removes a listener function from either the entire object, or from a specific property within the object." output="no">
		<cfargument name="property" default="" />
		<cfargument name="object" />
		<cfargument name="methodname" />
		<cfset Arguments.type="listener" />
		<cfset Arguments.action="remove" />
		<cfreturn addFunction(ArgumentCollection=Arguments) />
	</cffunction>
	
	<cffunction name="addFilter" hint="Adds a filter function to either the entire object as a whole, or a specific property within the object." output="no">
		<cfargument name="property" default="" />
		<cfargument name="object" />
		<cfargument name="methodname" />
		<cfset Arguments.type="filter" />
		<cfset Arguments.action="add" />
		<cfreturn addFunction(ArgumentCollection=Arguments) />
	</cffunction>
	<cffunction name="removeFilter" hint="Removes a filter function from either the entire object, or from a specific property within the object." output="no">
		<cfargument name="property" default="" />
		<cfargument name="object" />
		<cfargument name="methodname" />
		<cfset Arguments.type="filter" />
		<cfset Arguments.action="remove" />
		<cfreturn addFunction(ArgumentCollection=Arguments) />
	</cffunction>
	
	<!--- TRANSLATION --->
	
	<cffunction name="toStruct" output="no">
		<cfset var my = StructNew() />
		<cftry>
			<cfif StructCount(Arguments) gt 1>
				<cfif StructKeyExists(Arguments,"1")>
					<cfset Arguments.object = Arguments.1 />
					<cfset Arguments.depth = Arguments.2 />
				</cfif>
			<cfelseif StructCount(Arguments) eq 1>
				<cfif StructKeyExists(Arguments,"1")>
					<cfif isSimpleValue(Arguments.1) and isNumeric(Arguments.1)>
						<cfset Arguments.object = this />
						<cfset Arguments.depth = Arguments.1 />
					<cfelse>
						<cfset Arguments.object = Arguments.1 />
						<cfset Arguments.depth = 1 />
					</cfif>
				</cfif>
			<cfelseif StructCount(Arguments) eq 0>
				<cfset Arguments.object = this />
				<cfset Arguments.depth = 1 />
			</cfif>
			<cfparam name="Arguments.object" />
			<cfparam name="Arguments.depth" />
			<cfif isArray(Arguments.object)>
				<cfif Arguments.depth gt 0>
					<cfset my.struct = ArrayNew(1) />
					<cfloop from="1" to="#ArrayLen(Arguments.object)#" index="my.index">
						<cfset my.struct[my.index] = toStruct(Arguments.object[my.index], Arguments.depth-1) />
					</cfloop>
				<cfelse>
					<cfset my.struct = "[Array]" />
				</cfif>
			<cfelseif isObject(Arguments.object)>
				<cfif Arguments.depth gt 0>
					<cfset my.struct = StructNew() />
					<cfif isDefined("Arguments.object.toStruct")>
						<!--- Pi Component --->
						<!--- Add properties here, but listeners/filters later. --->
						<cfset my.struct.properties = Arguments.object.properties />
						<cfloop list="#Arguments.object.getPropertyList()#" index="my.property">
							<cfset my.struct[my.property] = toStruct(Arguments.object.get(my.property), Arguments.depth-1) />
						</cfloop>
						<!--- Global Functions --->
						<cfloop list="globalListeners,globalFilters" index="my.functionSet">
							<cfset my.struct[my.functionSet] = ArrayNew(1) />
							<cfloop from="1" to="#ArrayLen(this[my.functionSet])#" index="my.index">
								<cfset my.struct[my.functionSet][my.index] = StructNew() />
								<cfloop list="#StructKeyList(this[my.functionSet][my.index])#" index="my.argument">
									<cfif my.argument eq "object">
										<cfset my.object = this[my.functionSet][my.index][my.argument] />
										<cfif StructKeyExists(my.object,"getUUID") and my.object.getUUID() eq this.getUUID()>
											<cfset my.struct[my.functionSet][my.index][my.argument] = "[this]" />
										<cfelse>
											<!--- Do not go recursively, since listeners might listen to an object that listens back to this object. --->
											<cfset my.struct[my.functionSet][my.index][my.argument] = "[Object]" />
										</cfif>
									<cfelse>
										<cfset my.struct[my.functionSet][my.index][my.argument] = this[my.functionSet][my.index][my.argument] />
									</cfif>
								</cfloop>
							</cfloop>
						</cfloop>
						<!--- Property Functions --->
						<cfloop list="Listeners,Filters" index="my.functionSet">
							<cfset my.struct["property#my.functionSet#"] = StructNew() />
							<cfloop list="#StructKeyList(this[my.functionSet])#" index="my.property">
								<cfset my.struct["property#my.functionSet#"][my.property] = ArrayNew(1) />
								<cfloop from="1" to="#ArrayLen(this[my.functionSet][my.property])#" index="my.index">
									<cfset my.struct["property#my.functionSet#"][my.property][my.index] = StructNew() />
									<cfloop list="#StructKeyList(this[my.functionSet][my.property][my.index])#" index="my.argument">
										<cfif my.argument eq "object">
											<cfset my.object = this[my.functionSet][my.property][my.index][my.argument] />
											<cfif StructKeyExists(my.object,"getUUID") and my.object.getUUID() eq this.getUUID()>
												<cfset my.struct["property#my.functionSet#"][my.property][my.index][my.argument] = "[this]" />
											<cfelse>
												<!--- Do not go recursively, since listeners might listen to an object that listens back to this object. --->
												<cfset my.struct["property#my.functionSet#"][my.property][my.index][my.argument] = "[Object]" />
											</cfif>
										<cfelse>
											<cfset my.struct["property#my.functionSet#"][my.property][my.index][my.argument] = this[my.functionSet][my.property][my.index][my.argument] />
										</cfif>
									</cfloop>
								</cfloop>
							</cfloop>
						</cfloop>
					<cfelse>
						<cfloop list="#StructKeyList(Arguments.object)#" index="my.property">
							<cfset my.struct[my.property] = toStruct(Arguments.object[my.property], Arguments.depth-1) />
						</cfloop>
					</cfif>
				<cfelse>
					<cfset my.struct = "[Object]" />
				</cfif>
			<cfelseif isStruct(Arguments.object)>
				<cfif Arguments.depth gt 0>
					<cfset my.struct = StructNew() />
					<cfloop list="#StructKeyList(Arguments.object)#" index="my.index">
						<cfset my.struct[my.index] = toStruct(Arguments.object[my.index], Arguments.depth-1) />
					</cfloop>
				<cfelse>
					<cfset my.struct = "[Struct]" />
				</cfif>
			<cfelseif isSimpleValue(Arguments.object)>
				<cfset my.struct = Arguments.object />
			<cfelse>
				<cfset my.struct = "[null]" />
			</cfif>
			<cfreturn my.struct />
			
			<cfcatch>
				<cfrethrow />
				<!--- Debug Output --->
				<cfdump var="#my#">
				<cfdump var="#this[my.functionSet]#">
				<cfdump var="#cfcatch#">
				<cfabort>
			</cfcatch>
		</cftry>
	</cffunction>
	
</cfcomponent>