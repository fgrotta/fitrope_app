import 'package:fitrope_app/style.dart';
import 'package:flutter/material.dart';

enum CourseState {
  NULL,
  EXPIRED,
  CAN_SUBSCRIBE,
  FULL,
  SUBSCRIBED
}

class CourseCard extends StatefulWidget {
  final String title;
  final TextStyle? titleStyle;
  final String description;
  final TextStyle? descriptionStyle;
  final Function? onClick;
  final Function? onClickAction;
  final CourseState courseState;
  final int? capacity;
  final int? subscribed;
  final List<String>? subscribersNames;

  const CourseCard({
    super.key, 
    required this.title,
    this.courseState=CourseState.NULL,
    this.titleStyle,
    this.description="",
    this.descriptionStyle,
    this.onClick,
    this.onClickAction,
    this.capacity,
    this.subscribed,
    this.subscribersNames,
  });

  @override
  State<CourseCard> createState() => _CourseCardState();
}

class _CourseCardState extends State<CourseCard> {
  void showSubscribersDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Iscritti al corso'),
        content: widget.subscribersNames == null || widget.subscribersNames!.isEmpty
          ? const Text('Nessun iscritto')
          : SizedBox(
              width: 300,
              child: ListView(
                shrinkWrap: true,
                children: widget.subscribersNames!.map((name) => ListTile(title: Text(name))).toList(),
              ),
            ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Widget renderTitle() {
    if(widget.titleStyle != null) {
      return Text(widget.title, overflow: TextOverflow.visible, style: widget.titleStyle,);
    }

    return Text(widget.title, style: const TextStyle(color: Colors.white, ),);
  }

  Widget renderButton() {
    late String buttonText;
    late Color buttonColor;
    late Color buttonTextColor;
    bool canBeClicked = false;

    if(widget.courseState == CourseState.CAN_SUBSCRIBE) {
      canBeClicked = true;
      buttonText = 'Prenotati';
      buttonColor = actionColor;
      buttonTextColor = Colors.white;
    }
    else if(
      widget.courseState == CourseState.FULL ||
      widget.courseState == CourseState.EXPIRED
    ) {
      buttonText = 'Non disponibile';
      buttonColor = ghostColor;
      buttonTextColor = const Color.fromARGB(86, 255, 255, 255);
    }
    else if(widget.courseState == CourseState.SUBSCRIBED) {
      buttonText = 'Rimuovi iscrizione';
      buttonColor = dangerColor;
      buttonTextColor = Colors.white;
      canBeClicked = true;
    }

    return ElevatedButton(
      onPressed: canBeClicked ? () {
        if(widget.onClickAction != null) {
          widget.onClickAction!();
        }
      } : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(buttonColor),
        minimumSize: WidgetStateProperty.all(Size.zero),
        padding: WidgetStateProperty.all(const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 10)),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          )
        )
      ), 
      child: Text(buttonText, style: TextStyle(color: buttonTextColor),),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if(widget.onClick != null) {
          widget.onClick!();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: primaryColor,
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    renderTitle(),
                    if(widget.subscribersNames != null && widget.subscribersNames!.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.people),
                        tooltip: 'Vedi iscritti',
                        onPressed: showSubscribersDialog,
                      ),
                  ],
                ),
                if(widget.description != "") const SizedBox(height: 10,),
                if(widget.description != "") Text(widget.description, style: const TextStyle(color: Colors.white, ),)
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if(widget.capacity != null && widget.subscribed != null) Row(
                  children: [
                    Text("${widget.subscribed}/${widget.capacity}", style: const TextStyle(color: ghostColor),),
                    const SizedBox(width: 7.5,),
                    const Icon(Icons.people, color: ghostColor, size: 20,),
                  ],
                ),
                const SizedBox(height: 10,),
                if(widget.courseState != CourseState.NULL) renderButton()
              ],
            )
          ],
        )
      ),
    );
  }
}