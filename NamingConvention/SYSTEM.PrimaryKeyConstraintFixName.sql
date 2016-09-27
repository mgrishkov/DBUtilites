alter procedure SYSTEM.PrimaryKeyConstraintFixName
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
    
    create table #primaryKeyColumn 
    (
          [DatabaseName]     sysname
        , [SchemaName]       sysname
        , [TableName]        sysname
        , [ColumnName]       sysname
        , [ColumnGuid]       uniqueidentifier
        , [ColumnPropertyID] int
        , [SortOrder]        int
        , [KeyName]          sysname  
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
        truncate table #primaryKeyColumn;
        insert into #primaryKeyColumn (DatabaseName, SchemaName, TableName, ColumnName, ColumnGuid, ColumnPropertyID, SortOrder, KeyName)
            exec [sys].[sp_primary_keys_rowset] @table_schema = @schemaName
                                              , @table_name   = @tableName;

        if(not exists (select 1 from #primaryKeyColumn))
            goto nextTable;
    
        insert into #nameConventionDeviation (SchemaName, TableName, OriginalKeyName, BeautifiedKeyName)
            select kc.SchemaName
                 , kc.TableName
                 , kc.KeyName
                 , 'PK#' + @tableName + (select '@' + kc.ColumnName from #primaryKeyColumn kc Order by kc.SortOrder for xml path(''))
              from #primaryKeyColumn kc
             where 1 = 1
             group by kc.SchemaName
                    , kc.TableName
                    , kc.KeyName;
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
     where 1 = 1
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

exec SYSTEM.PrimaryKeyConstraintFixName