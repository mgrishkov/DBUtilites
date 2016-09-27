CREATE procedure SYSTEM.ForeignKeyConstraintFixName
  @pIsExecuteScript bit = 0
as set nocount                 on
   set xact_abort              on
   set ansi_nulls              on
   set ansi_warnings           on
   set ansi_padding            on
   set ansi_null_dflt_on       on
   set arithabort              on
   set quoted_identifier       on
   set concat_null_yields_null on
   set implicit_transactions   off
   set cursor_close_on_commit  off
begin

    declare @tableName         sysname
          , @schemaName        sysname
          , @originalKeyName   sysname
          , @beautifiedKeyName sysname
          , @script            nvarchar(max);
    
    create table #nameConventionDeviation
    (
          [SchemaName]        sysname
        , [TableName]         sysname
        , [OriginalKeyName]   sysname 
        , [BeautifiedKeyName] sysname
        , [Script]            as ('exec sys.sp_rename @objname = N''' + SchemaName + '.' + OriginalKeyName +''', @newname = N''' + BeautifiedKeyName + ''', @objtype = ''OBJECT'';' )
    );
    
    create table #foreignKeyColumn 
    (
          [PkDatabaseName]    sysname
        , [PkSchemaName]      sysname
        , [PkTableName]       sysname
        , [PkColumnName]      sysname
        , [PkColumnGuid]      uniqueidentifier 
        , [PkColumnPopertyID] int	
        , [FkDatabaseName]    sysname
        , [FkSchemaName]      sysname
        , [FkTableName]       sysname
        , [FkColumnName]      sysname
        , [FkColumnGuid]      uniqueidentifier 
        , [FkColumnPopertyID] int	
        , [SortOrder]         int	
        , [UpdateRule]        nvarchar(32)
        , [DeleteRule]        nvarchar(32)
        , [PkName]            sysname
        , [FkName]            sysname 
        , [Deferability]      int
    );
    
    declare cTables cursor fast_forward 
        for select s.name
                 , t.name
              from sys.tables t
                   inner join sys.schemas s
                on t.schema_id = s.schema_id
             order by t.name;
    open cTables;
    
    fetch next from cTables
        into @schemaName
           , @tableName;
    
    while(@@fetch_status = 0)
    begin
        truncate table #foreignKeyColumn;
        insert into #foreignKeyColumn (PkDatabaseName, PkSchemaName, PkTableName, PkColumnName, PkColumnGuid, PkColumnPopertyID, FkDatabaseName, FkSchemaName, FkTableName, FkColumnName, FkColumnGuid, FkColumnPopertyID, SortOrder, UpdateRule, DeleteRule, PkName, FkName, Deferability)
            exec [sys].[sp_foreign_keys_rowset] @pk_table_name   = @tableName
                                              , @pk_table_schema = @schemaName;
        
        if(not exists (select 1 from #foreignKeyColumn))
            goto nextTable;

        insert into #nameConventionDeviation (SchemaName, TableName, OriginalKeyName, BeautifiedKeyName)
            select fk.FkSchemaName
                 , fk.FkTableName
                 , fk.FkName
                 , 'FK' 
                 + '#' + fk.FkTableName 
                 + (select '@' + fk1.FkColumnName
                      from #foreignKeyColumn fk1
                     where fk1.FkName = fk.FkName
                     order by fk1.SortOrder
                       for xml path(''))
                 + '#' + fk.PkTableName
                 + (select '@' + fk1.PkColumnName
                      from #foreignKeyColumn fk1
                     where fk1.FkName = fk.FkName
                     order by fk1.SortOrder
                       for xml path(''))
              from #foreignKeyColumn fk
             where 1 = 1
             group by fk.FkSchemaName
                    , fk.FkTableName
                    , fk.PkTableName
                    , fk.FkName;

nextTable:    
        fetch next from cTables
            into @schemaName
               , @tableName;
    end;
       
    close cTables;
    deallocate cTables;	

    delete from #nameConventionDeviation
     where OriginalKeyName = BeautifiedKeyName;

    select SchemaName
         , TableName
         , OriginalKeyName
         , BeautifiedKeyName
         , Script     
      from #nameConventionDeviation
     order by SchemaName
            , TableName;

    set @script = (select char(10) + d.Script
                     from #nameConventionDeviation d
                    order by d.SchemaName
                           , d.TableName
                      for xml path (''));

    if(@pIsExecuteScript = 1)
    begin
        exec (@script);
    end;

	return 0; 
end
GO
