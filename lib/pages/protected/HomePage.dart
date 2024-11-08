import 'package:fitrope_app/pages/protected/UserDetailPage.dart';
import 'package:fitrope_app/router.dart';
import 'package:fitrope_app/state/store.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/fitropeUser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';
import 'package:flutter_design_system/components/items_showcase.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late FitropeUser user;

  @override
  void initState() {
    user = store.state.user!;
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(pagePadding),
      child: Column(
        children: [
          // HEADER
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Home', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30, color: Colors.white),),
              GestureDetector(
                child: CircleAvatar(
                  backgroundColor: const Color.fromARGB(255, 113, 129, 219),
                  child: Text(user.name[0] + user.lastName[0]),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserDetailPage()),
                  );
                },
              )
            ],
          ),

          // ABBONAMENTO
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(top: 20, bottom: 10),
                width: double.infinity,
                child: const Text('Il mio abbonamento', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
              ),
              const CustomCard(title: 'Abbonamento ad entrate', description: 'Entrate disponibili: 50',),
              const SizedBox(height: 30,),
            ],
          ),

          // CORSI
          Column(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 10),
                width: double.infinity,
                child: const Text('I miei corsi', textAlign: TextAlign.left, style: TextStyle(color: Colors.white, fontSize: 20),),
              ),
              const CustomCard(title: 'Corso Fitrope 1', description: '15.00 - 15.30',),
              const SizedBox(height: 10,),
              const CustomCard(title: 'Corso Fitrope 1', description: '15.00 - 15.30',),
              const SizedBox(height: 10,),
              const CustomCard(title: 'Corso Fitrope 1', description: '15.00 - 15.30',),
              const SizedBox(height: 10,),
              const CustomCard(title: 'Corso Fitrope 1', description: '15.00 - 15.30',),
            ],
          ),
        ],
      ),
    );
  }
}