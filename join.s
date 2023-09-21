* join - join the lines of two files
*
* Itagaki Fumihiko 28-Jan-95  Create.
* 1.0
*
* Usage: join [ -1 <フィールド番号> ] [ -2 <フィールド番号> ] [ -j[1|2] <フィールド番号> ]
*             [ -a {1|2} ] [ -v {1|2} ] [ -o {1|2}.<フィールド番号> ... ] [ -e <文字列> ]
*             [ -t <文字> ] [ -Z ] [ -- ] <ファイル1> <ファイル2>

.include doscall.h
.include chrcode.h
.include stat.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strfor1
.xref memcmp
.xref memmovi
.xref atou
.xref strip_excessive_slashes

STACKSIZE	equ	2048

INPBUF_SIZE	equ	8192
OUTBUF_SIZE	equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_Z		equ	0	*  -Z

.offset 0
fd_Pathname:		ds.l	1
fd_ReadBuffTopP:	ds.l	1
fd_ReadPtr:		ds.l	1
fd_ReadDataRemain:	ds.l	1
fd_UngetcBuf:		ds.l	1
fd_LineBuffTopP:	ds.l	1
fd_LineBuffSize:	ds.l	1
fd_LineBuffDataP:	ds.l	1
fd_LineBuffFree:	ds.l	1
fd_ComFieldNo:		ds.l	1
fd_LastLineP:		ds.l	1
fd_FileNo:		ds.w	1
fd_Handle:		ds.w	1
fd_EOF:			ds.b	1
fd_UngetcFlag:		ds.b	1
fd_flag_a:		ds.b	1
fd_flag_v:		ds.b	1
fd_EofOnCtrlZ:		ds.b	1
fd_EofOnCtrlD:		ds.b	1
sizeof_fd:

.offset 0
line_Length:		ds.l	1
line_NumFields:		ds.l	1
line_ComFieldTopP:	ds.l	1
sizeof_line_header:

.offset 0
field_Length:		ds.l	1
sizeof_field_header:

*****************************************************************
.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bsstop(pc),a6
		lea	stack_bottom(a6),a7		*  A7 := スタックの底
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		*
		moveq	#0,d5				*  D5.L : フラグ
		clr.w	delimiter(a6)
		clr.l	null_field_length(a6)

		lea	file1(a6),a2
		moveq	#1,d0
		lea	inpbuf1(a6),a1
		bsr	init_fd

		lea	file2(a6),a2
		moveq	#2,d0
		lea	inpbuf2(a6),a1
		bsr	init_fd

		*  とりあえず field list に最大メモリを割り当てておく
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		move.l	d0,d3				*  D3.L : field list の容量
		cmp.l	#2,d3
		blo	insufficient_memory

		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outlist(a6)
		movea.l	d0,a1
		moveq	#0,d4				*  D4.L : field list count
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		move.b	1(a0),d0
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		lea	file1(a6),a2
		cmp.b	#'1',d0
		beq	set_com_fieldno

		lea	file2(a6),a2
		cmp.b	#'2',d0
		beq	set_com_fieldno

		cmp.b	#'j',d0
		beq	option_j_found

		moveq	#fd_flag_a,d2
		cmp.b	#'a',d0
		beq	option_av_found

		moveq	#fd_flag_v,d2
		cmp.b	#'v',d0
		beq	option_av_found

		cmp.b	#'o',d0
		beq	option_o_found

		cmp.b	#'e',d0
		beq	option_e_found

		cmp.b	#'t',d0
		beq	option_t_found

		cmp.b	#'Z',d0
		beq	option_Z_found

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
		bra	usage

option_j_found:
		tst.b	(a0)
		beq	option_j_fieldno

		bsr	atofd
		bne	option_j_fieldno_1

		subq.l	#1,d7
		bcs	too_few_args
		bra	set_com_fieldno_1

option_j_fieldno:
		subq.l	#1,d7
		bcs	too_few_args

		addq.l	#1,a0
		bsr	aton
option_j_fieldno_1:
		move.l	d1,file1+fd_ComFieldNo(a6)
		move.l	d1,file2+fd_ComFieldNo(a6)
		bra	decode_opt_loop1

set_com_fieldno:
		bsr	optarg
set_com_fieldno_1:
		bsr	aton
		move.l	d1,fd_ComFieldNo(a2)
		beq	bad_arg
		bra	decode_opt_loop1

option_av_found:
		bsr	optarg
		bsr	atofd
		bne	bad_arg

		st	(a2,d2.l)
		bra	decode_opt_loop1

option_o_found:
		bsr	optarg
		addq.l	#1,d7
		bsr	atou
parse_outlist_loop:
		bne	bad_arg

		bsr	select_file
		bne	bad_arg

		cmpi.b	#'.',(a0)+
		bne	bad_arg

		move.l	d1,d2
		bsr	aton

		subq.l	#6,d3
		blo	insufficient_memory

		move.w	d2,(a1)+
		move.l	d1,(a1)+
		addq.l	#1,d4
		subq.l	#1,d7
		beq	decode_opt_loop1

		bsr	atou
		bmi	decode_opt_loop1
		bra	parse_outlist_loop

option_e_found:
		bsr	optarg
		move.l	a0,null_field_output(a6)
		bsr	strlen
		move.l	d0,null_field_length(a6)
		addq.l	#1,d0
		adda.l	d0,a0
		bra	decode_opt_loop1

option_t_found:
		bsr	optarg
		moveq	#0,d0
		move.b	(a0)+,d0
		bsr	issjis
		bne	option_t_1

		lsl.w	#8,d0
		move.b	(a0)+,d0
option_t_1:
		tst.b	d0
		bne	option_t_2

		subq.l	#1,a0
option_t_2:
		tst.b	(a0)+
		bne	bad_arg

		move.w	d0,delimiter(a6)
		bra	decode_opt_loop1

option_Z_found:
		bset	#FLAG_Z,d5
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1
****************
optarg:
		tst.b	(a0)
		bne	optarg_return

		subq.l	#1,d7
		bcs	too_few_args

		addq.l	#1,a0
optarg_return:
aton_ok:
		rts
****************
aton:
		bsr	atou
		bne	bad_arg

		tst.b	(a0)+
		bne	bad_arg

		tst.l	d1
		bne	aton_ok
bad_arg:
		lea	msg_bad_arg(pc),a0
		bra	werror_usage
****************
atofd:
		bsr	aton
select_file:
		lea	file1(a6),a2
		cmp.l	#1,d1
		beq	select_file_return

		lea	file2(a6),a2
		cmp.l	#2,d1
select_file_return:
		rts
****************
decode_opt_done:
		*  field list を fix する
		tst.l	d4
		bne	fix_outlist_1

		move.l	outlist(a6),-(a7)
		DOS	_MFREE
		addq.l	#4,a7
		clr.l	outlist(a6)
		bra	fix_outlist_done

fix_outlist_1:
		subq.l	#2,d3
		blo	insufficient_memory

		clr.w	(a1)+
		suba.l	outlist(a6),a1
		move.l	a1,-(a7)
		move.l	outlist(a6),-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
fix_outlist_done:
		subq.l	#2,d7
		blo	too_few_args
		bhi	too_many_args
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	move_stdin_done

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
move_stdin_done:
	*
	*  入力をオープン
	*
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		lea	file1(a6),a2
		bsr	open_input
		movea.l	a1,a0
		lea	file2(a6),a2
		bsr	open_input
		move.w	file1+fd_Handle(a6),d0
		cmp.w	file2+fd_Handle(a6),d0
		beq	both_stdin
	*
	*  出力をチェック
	*
		moveq	#1,d0
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering(a6)
		bne	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_topP(a6)
		move.l	d0,outbuf_writeP(a6)
outbuf_ok:
	*
	*  フィールドバッファを確保する
	*
		move.l	#$00ffffff,d0
		bsr	malloc
		sub.l	#$81000000,d0
		move.l	d0,d1
		lsr.l	#1,d1
		cmp.l	#16,d1
		blo	insufficient_memory

		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,file1+fd_LineBuffTopP(a6)
		move.l	d1,file1+fd_LineBuffSize(a6)
		add.l	d1,d0
		move.l	d0,file2+fd_LineBuffTopP(a6)
		move.l	d1,file2+fd_LineBuffSize(a6)
	*
	*  メイン処理
	*
		bsr	join
		bsr	flush_outbuf
		moveq	#0,d0
exit_program:
		move.w	d0,-(a7)
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
		addq.l	#4,a7
exit_program_1:
		DOS	_EXIT2

both_stdin:
		lea	msg_both_stdin(pc),a0
		bsr	werror_myname_and_msg
exit_2:
		moveq	#2,d0
		bra	exit_program

too_many_args:
		lea	msg_too_many_args(pc),a0
		bra	werror_usage

too_few_args:
		lea	msg_too_few_args(pc),a0
werror_usage:
		bsr	werror_myname_and_msg
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d0
		bra	exit_program
****************************************************************
init_fd:
		move.w	d0,fd_FileNo(a2)
		move.l	a1,fd_ReadBuffTopP(a2)
		move.l	a1,fd_ReadPtr(a2)
		move.l	#1,fd_ComFieldNo(a2)
		sf	fd_flag_a(a2)
		sf	fd_flag_v(a2)
		rts
****************************************************************
open_input:
		move.l	a0,fd_Pathname(a2)
		cmpi.b	#'-',(a0)
		bne	open_file

		tst.b	1(a0)
		bne	open_file

		lea	msg_stdin(pc),a0
		move.l	stdin(a6),d0
		bra	input_open

open_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
input_open:
		tst.l	d0
		bmi	open_input_fail

		move.w	d0,fd_Handle(a2)
		btst	#FLAG_Z,d5
		sne	fd_EofOnCtrlZ(a2)
		sf	fd_EofOnCtrlD(a2)
		bsr	is_chrdev
		beq	input_open_1			*  -- ブロック・デバイス

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_open_1

		st	fd_EofOnCtrlZ(a2)
		st	fd_EofOnCtrlD(a2)
input_open_1:
		clr.l	fd_ReadDataRemain(a2)
		sf	fd_UngetcFlag(a2)
		sf	fd_EOF(a2)
		rts

open_input_fail:
		lea	msg_open_fail(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	exit_2
****************************************************************
* join
****************************************************************
join:
		lea	file2(a6),a2
		bsr	getline
		movea.l	a2,a3
		lea	file1(a6),a2
join_loop1:
		bsr	getline
join_loop2:
		tst.l	fd_LastLineP(a2)
		beq	join_nomore

		tst.l	fd_LastLineP(a3)
		beq	join_reduce_file

		movea.l	fd_LineBuffTopP(a2),a0
		movea.l	fd_LineBuffTopP(a3),a1
		bsr	compare
		blo	join_reduce_file
		bhi	join_reduce_exfile
		bra	join_pair

join_nomore:
		tst.l	fd_LastLineP(a3)
		bne	join_reduce_exfile
		rts

join_reduce_exfile:
		exg	a2,a3
join_reduce_file:
		tst.b	fd_flag_v(a2)
		bne	join_reduce_file_output

		tst.b	fd_flag_a(a2)
		beq	join_loop1
join_reduce_file_output:
		sf	d3
		move.l	outlist(a6),d0
		beq	output_unpairble_1

		movea.l	d0,a4
output_unpairble_with_list_loop:
		move.w	(a4)+,d1
		beq	output_unpairble_done

		move.l	(a4)+,d0
		cmp.w	fd_FileNo(a2),d1
		beq	output_unpairble_with_list_1

		moveq	#0,d0
output_unpairble_with_list_1:
		movea.l	fd_LineBuffTopP(a2),a0
		bsr	get_field_and_output
		bra	output_unpairble_with_list_loop

output_unpairble_1:
		movea.l	fd_LineBuffTopP(a2),a0
		movea.l	line_ComFieldTopP(a0),a0
		bsr	output_field_1
		movea.l	fd_LineBuffTopP(a2),a0
		bsr	output_remainder_fields
output_unpairble_done:
		bsr	put_newline
		bra	join_loop1

join_pair:
		lea	file1(a6),a2
		lea	file2(a6),a3
		bsr	get_all_pairble_lines
		exg	a2,a3
		move.l	d2,-(a7)
		bsr	get_all_pairble_lines
		move.l	(a7)+,d3
		exg	a2,a3

		move.b	fd_flag_v(a2),d0
		or.b	fd_flag_v(a3),d0
		bne	join_pair_done

		movea.l	fd_LineBuffTopP(a2),a0
join_pair_loop1:
		movea.l	fd_LineBuffTopP(a3),a1
		move.l	d2,-(a7)
join_pair_loop2:
		movem.l	d2-d3/a0-a1,-(a7)
		bsr	output_pair
		movem.l	(a7)+,d2-d3/a0-a1
		adda.l	line_Length(a1),a1
		subq.l	#1,d2
		bcc	join_pair_loop2

		move.l	(a7)+,d2
		adda.l	line_Length(a0),a0
		subq.l	#1,d3
		bcc	join_pair_loop1
join_pair_done:
		bsr	reset_line
		exg	a2,a3
		bsr	reset_line
		bra	join_loop2
*****************************************************************
compare:
		move.l	line_ComFieldTopP(a0),d0
		beq	compare_01

		movea.l	d0,a0
		move.l	(a0)+,d0
compare_01:
		move.l	line_ComFieldTopP(a1),d1
		beq	compare_02

		movea.l	d1,a1
		move.l	(a1)+,d1
compare_02:
		cmp.l	d0,d1
		beq	memcmp
		blo	compare_2
compare_1:
		bsr	memcmp
		bne	compare_1_return

		moveq	#0,d0
		sub.b	#1,d0
compare_1_return:
		rts

compare_2:
		move.l	d1,d0
		bsr	memcmp
		bne	compare_2_return

		moveq	#1,d0
		sub.b	#0,d0
compare_2_return:
		rts
*****************************************************************
reset_line:
		move.l	fd_LastLineP(a2),d0
		beq	reset_line_return

		movea.l	d0,a1
		movea.l	fd_LineBuffTopP(a2),a0
		tst.l	line_ComFieldTopP(a1)
		beq	reset_line_1

		move.l	a1,d0
		sub.l	a0,d0
		sub.l	d0,line_ComFieldTopP(a1)
reset_line_1:
		move.l	line_Length(a1),d0
		bsr	memmovi
		move.l	a0,fd_LineBuffDataP(a2)
		move.l	fd_LineBuffSize(a2),d1
		sub.l	d0,d1
		move.l	d1,fd_LineBuffFree(a2)
reset_line_return:
		rts
*****************************************************************
get_all_pairble_lines:
		moveq	#0,d2
get_all_pairble_lines_loop:
		move.l	d2,-(a7)
		bsr	getline2
		move.l	(a7)+,d2
		tst.l	fd_LastLineP(a2)
		beq	get_all_pairble_lines_done

		addq.l	#1,d2
		movea.l	fd_LineBuffTopP(a3),a1
		bsr	compare
		beq	get_all_pairble_lines_loop

		subq.l	#1,d2
get_all_pairble_lines_done:
		rts
*****************************************************************
getline:
		move.l	fd_LineBuffTopP(a2),fd_LineBuffDataP(a2)
		move.l	fd_LineBuffSize(a2),fd_LineBuffFree(a2)
getline2:
		bsr	getc
		bmi	getline_eof

		bsr	ungetc
		movea.l	fd_LineBuffDataP(a2),a4
		move.l	fd_LineBuffFree(a2),d4
		sub.l	#sizeof_line_header,d4
		blo	insufficient_memory

		lea	sizeof_line_header(a4),a4
		suba.l	a5,a5				*  A5 : ComFieldTopP
		moveq	#0,d3				*  D3.L : field number counter
getline_loop1:
		moveq	#0,d2				*  D2.L : field length counter
getline_loop2:
		bsr	getc
		bmi	getline_delimiter

		cmp.b	#LF,d0
		beq	getline_delimiter

		cmp.b	#CR,d0
		beq	getline_cr

		bsr	issjis
		bne	getline_1

		move.l	d0,d1
		bsr	getc
		bpl	getline_sjis

		bsr	ungetc
		bra	getline_store

getline_sjis:
		cmpi.w	#$ff,delimiter(a6)
		bls	getline_mb_store

		lsl.w	#8,d1
		or.w	d1,d0
		cmp.w	delimiter(a6),d0
		beq	getline_delimiter

		lsr.w	#8,d1
getline_mb_store:
		bsr	check_getline_store
		move.b	d1,(a4)+
		addq.l	#1,d2
		tst.l	d0
		bmi	getline_delimiter
		bra	getline_store

getline_cr:
		bsr	getc
		cmp.l	#LF,d0
		beq	getline_delimiter

		bsr	ungetc
getline_1:
		move.w	delimiter(a6),d1
		beq	getline_check_default_delimiter

		cmpi.w	#$ff,d1
		bhi	getline_store

		cmp.b	d1,d0
		bne	getline_store
		bra	getline_delimiter

getline_check_default_delimiter:
		cmp.b	#HT,d0
		beq	getline_delimiter

		cmp.b	#$20,d0
		beq	getline_delimiter
getline_store:
		bsr	check_getline_store
		move.b	d0,(a4)+
		addq.l	#1,d2
		bra	getline_loop2

getline_delimiter:
		tst.l	d2
		beq	getline_delimiter_next

		movea.l	a4,a0
		suba.l	d2,a0
		subq.l	#sizeof_field_header,a0
		move.l	d2,field_Length(a0)			*  このフィールドの長さ
		btst	#0,d2
		beq	getline_delimiter_1

		subq.l	#1,d4
		blo	insufficient_memory

		addq.l	#1,a4
getline_delimiter_1:
		addq.l	#1,d3
		cmp.l	fd_ComFieldNo(a2),d3
		bne	getline_delimiter_next

		movea.l	a0,a5
getline_delimiter_next:
		tst.l	d0
		bmi	getline_done

		cmp.b	#LF,d0
		beq	getline_done

		tst.l	d2
		beq	getline_loop2
		bra	getline_loop1

getline_done:
		movea.l	fd_LineBuffDataP(a2),a0
		move.l	a4,d0
		sub.l	a0,d0
		move.l	d0,line_Length(a0)		*  このlineのバイト数
		move.l	d3,line_NumFields(a0)		*  このlineのフィールド数
		move.l	a5,line_ComFieldTopP(a0)	*  このlineの比較フィールドのアドレス
		move.l	a0,fd_LastLineP(a2)
		move.l	a4,fd_LineBuffDataP(a2)
		move.l	d4,fd_LineBuffFree(a2)
		rts

getline_eof:
		clr.l	fd_LastLineP(a2)
		rts

check_getline_store:
		tst.l	d2
		bne	check_getline_store_1

		subq.l	#sizeof_field_header,d4
		blo	insufficient_memory

		addq.l	#sizeof_field_header,a4
check_getline_store_1:
		subq.l	#1,d4
		blo	insufficient_memory
		rts
*****************************************************************
ungetc:
		move.l	d0,fd_UngetcBuf(a2)
		st	fd_UngetcFlag(a2)
		rts
*****************************************************************
getc:
		tst.b	fd_UngetcFlag(a2)
		beq	getc_1

		sf	fd_UngetcFlag(a2)
		move.l	fd_UngetcBuf(a2),d0
		rts

getc_1:
		movea.l	fd_ReadPtr(a2),a0
		subq.l	#1,fd_ReadDataRemain(a2)
		bcc	getc_get1

		tst.b	fd_EOF(a2)
		bne	getc_eof

		movea.l	fd_ReadBuffTopP(a2),a0
		move.l	#INPBUF_SIZE,-(a7)
		move.l	a0,-(a7)
		move.w	fd_Handle(a2),-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,fd_ReadDataRemain(a2)
		bmi	read_fail

		tst.b	fd_EofOnCtrlZ(a2)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	fd_EofOnCtrlD(a2)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		subq.l	#1,fd_ReadDataRemain(a2)
		bcs	getc_eof
getc_get1:
		moveq	#0,d0
		move.b	(a0)+,d0
		move.l	a0,fd_ReadPtr(a2)
		tst.l	d0
		rts

getc_eof:
		st	fd_EOF(a2)
		clr.l	fd_ReadDataRemain(a2)
		moveq	#-1,d0
		rts

read_fail:
		movea.l	fd_Pathname(a2),a0
		lea	msg_read_fail(pc),a2
		bsr	werror_myname_word_colon_msg
		bra	exit_3
*****************************************************************
trunc:
		move.l	fd_ReadDataRemain(a2),d1
		beq	trunc_done

		movea.l	fd_ReadPtr(a2),a1
trunc_find_loop:
		cmp.b	(a1)+,d0
		beq	trunc_found

		subq.l	#1,d1
		bne	trunc_find_loop
trunc_done:
		rts

trunc_found:
		subq.l	#1,a1
		move.l	a1,d0
		sub.l	a0,d0
		move.l	d0,fd_ReadDataRemain(a2)
trunc_eof:
		st	fd_EOF(a2)
		rts
*****************************************************************
get_field_and_output:
		tst.l	d0
		beq	output_null_field

		cmp.l	line_NumFields(a0),d0
		bhi	output_null_field

		lea	sizeof_line_header(a0),a0
get_field_loop:
		subq.l	#1,d0
		beq	output_field_1

		move.l	(a0)+,d1
		addq.l	#1,d1
		bclr	#0,d1
		adda.l	d1,a0
		bra	get_field_loop

output_field_1:
		cmpa.l	#0,a0
		beq	output_null_field

		move.l	(a0)+,d1
		bne	output_field_2
output_null_field:
		movea.l	null_field_output(a6),a0
		move.l	null_field_length(a6),d1
output_field_2:
		tst.b	d3
		beq	output_field_3

			move.w	delimiter(a6),d0
			bne	put_delimiter_1

			moveq	#$20,d0
			bsr	putc
			bra	output_field_3

put_delimiter_1:
			ror.w	#8,d0
			tst.b	d0
			beq	put_delimiter_2

			bsr	putc
put_delimiter_2:
			ror.w	#8,d0
			bsr	putc
			bra	output_field_3

output_field_loop:
		move.b	(a0)+,d0
		bsr	putc
output_field_3:
		subq.l	#1,d1
		bcc	output_field_loop

		st	d3
output_remainder_fields_done:
		rts
*****************************************************************
output_remainder_fields:
		move.l	line_NumFields(a0),d2
		movea.l	line_ComFieldTopP(a0),a1
		lea	sizeof_line_header(a0),a0
output_remainder_fields_loop:
		subq.l	#1,d2
		bcs	output_remainder_fields_done

		cmpa.l	a1,a0
		bne	output_remainder_fields_1

		move.l	(a0)+,d1
		addq.l	#1,d1
		bclr	#0,d1
		adda.l	d1,a0
		bra	output_remainder_fields_loop

output_remainder_fields_1:
		move.l	(a0)+,d1
		move.l	d1,-(a7)
		bsr	output_field_2
		move.l	(a7)+,d1
		btst	#0,d1
		beq	output_remainder_fields_loop

		addq.l	#1,a0
		bra	output_remainder_fields_loop
*****************************************************************
output_pair:
		sf	d3
		move.l	outlist(a6),d0
		beq	output_pair_default

		movea.l	d0,a4
output_pair_with_list_loop:
		moveq	#0,d1
		move.w	(a4)+,d1
		beq	output_pair_done

		subq.w	#1,d1
		beq	output_pair_with_list_1

		exg	a0,a1
output_pair_with_list_1:
		move.l	(a4)+,d0
		movem.l	d1/a0-a1,-(a7)
		bsr	get_field_and_output
		movem.l	(a7)+,d1/a0-a1
		tst.w	d1
		beq	output_pair_with_list_loop

		exg	a0,a1
		bra	output_pair_with_list_loop

output_pair_default:
		move.l	a0,-(a7)
		movea.l	line_ComFieldTopP(a0),a0
		bsr	output_field_1
		movea.l	(a7)+,a0
		move.l	a1,-(a7)
		bsr	output_remainder_fields
		movea.l	(a7)+,a0
		bsr	output_remainder_fields
output_pair_done:
*****************************************************************
put_newline:
		moveq	#CR,d0
		bsr	putc
		moveq	#LF,d0
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering(a6)
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		bra	putc_done

putc_buffering:
		tst.l	outbuf_free(a6)
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_writeP(a6),a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_writeP(a6)
		subq.l	#1,outbuf_free(a6)
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
flush_outbuf:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering(a6)
		beq	flush_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free(a6),d0
		beq	flush_return

		move.l	d0,-(a7)
		move.l	outbuf_topP(a6),-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_topP(a6),outbuf_writeP(a6)
		move.l	#OUTBUF_SIZE,outbuf_free(a6)
flush_return:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
insufficient_memory:
		lea	msg_no_memory(pc),a0
		bsr	werror_myname_and_msg
		bra	exit_3
*****************************************************************
write_fail:
		bsr	werror_myname
		lea	msg_write_fail(pc),a0
		bsr	werror
exit_3:
		moveq	#3,d0
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
werror_myname_word_colon_msg:
		bsr	werror_myname_and_msg
		move.l	a0,-(a7)
		lea	str_colon(pc),a0
		bsr	werror
		movea.l	a2,a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
is_chrdev:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## join 1.0 ##  Copyright(C)1995 by Itagaki Fumihiko',0

.even
msg_myname:		dc.b	'join'
str_colon:		dc.b	': ',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_bad_arg:		dc.b	'引数が正しくありません',0
msg_too_few_args:	dc.b	'引数が足りません',0
msg_too_many_args:	dc.b	'引数が多過ぎます',0
msg_open_fail:		dc.b	'オープンできません',CR,LF,0
msg_both_stdin:		dc.b	'両方に標準入力を指定することはできません',CR,LF,0
msg_read_fail:		dc.b	'入力エラー',CR,LF,0
msg_write_fail:		dc.b	'出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_usage:
	dc.b	CR,LF
	dc.b	'使用法:  join [-1 <#>] [-2 <#>] [-j[1|2] <#>] [-a {1|2}] [-v {1|2}]',CR,LF
	dc.b	'              [-o {1|2}.<#> ...] [-e <文字列>] [-t <文字>] [-Z] [--]',CR,LF
	dc.b	'              <ファイル1> <ファイル2>',CR,LF,0
*****************************************************************
.bss
.even
bsstop:

.offset 0
stdin:			ds.l	1
outbuf_topP:		ds.l	1
outbuf_writeP:		ds.l	1
outbuf_free:		ds.l	1
outlist:		ds.l	1
null_field_output:	ds.l	1
null_field_length:	ds.l	1
delimiter:		ds.w	1
.even
file1:			ds.l	sizeof_fd
.even
file2:			ds.l	sizeof_fd
inpbuf1:		ds.b	INPBUF_SIZE
inpbuf2:		ds.b	INPBUF_SIZE
do_buffering:		ds.b	1
.even
			ds.b	STACKSIZE
.even
stack_bottom:

.bss
		ds.b	stack_bottom
*****************************************************************

.end start
