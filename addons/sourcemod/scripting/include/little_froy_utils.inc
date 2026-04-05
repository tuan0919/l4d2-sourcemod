#include <sourcemod>

enum StringExplodeType
{
    StringExplodeType_Int,
    StringExplodeType_Float,
    StringExplodeType_String
}

stock int explode_string_to_list(const char[] text, const char[] split, ArrayList output, int buffer_size, StringExplodeType type, int max_items = 0)
{
    if(buffer_size < 1 || type < StringExplodeType_Int || type > StringExplodeType_String)
    {
        return 0;
    }
    int reloc_idx = 0;
    int idx = 0;
    int total = 0;
    char[] buffer = new char[buffer_size];
    while((idx = SplitString(text[reloc_idx], split, buffer, buffer_size)) != -1)
    {
        switch(type)
        {
            case StringExplodeType_Int:
            {
                output.Push(StringToInt(buffer));
            }
            case StringExplodeType_Float:
            {
                output.Push(StringToFloat(buffer));
            }
            case StringExplodeType_String:
            {
                output.PushString(buffer);
            }
        }
        total++;
        if(max_items > 0 && total == max_items)
        {
            return total;
        }
        reloc_idx += idx;
    }
    switch(type)
    {
        case StringExplodeType_Int:
        {
            output.Push(StringToInt(text[reloc_idx]));
        }
        case StringExplodeType_Float:
        {
            output.Push(StringToFloat(text[reloc_idx]));
        }
        case StringExplodeType_String:
        {
            output.PushString(text[reloc_idx]);
        }
    }
    total++;
    return total;
}

stock int explode_string_to_cell_array(const char[] text, const char[] split, any[] output, int max_items, int buffer_size, StringExplodeType type)
{
    if(max_items < 1 || buffer_size < 1 || type < StringExplodeType_Int || type > StringExplodeType_Float)
    {
        return 0;
    }
    int reloc_idx = 0;
    int idx = 0;
    int total = 0;
    char[] buffer = new char[buffer_size];
    while((idx = SplitString(text[reloc_idx], split, buffer, buffer_size)) != -1)
    {
        switch(type)
        {
            case StringExplodeType_Int:
            {
                output[total++] = StringToInt(buffer);
            }
            case StringExplodeType_Float:
            {
                output[total++] = StringToFloat(buffer);
            }
        }
        if(total == max_items)
        {
            return total;
        }
        reloc_idx += idx;
    }
    switch(type)
    {
        case StringExplodeType_Int:
        {
            output[total++] = StringToInt(text[reloc_idx]);
        }
        case StringExplodeType_Float:
        {
            output[total++] = StringToFloat(text[reloc_idx]);
        }
    }
    return total;
}