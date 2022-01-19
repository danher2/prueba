package questionMaker;


import java.util.Scanner;

public class SimpleQuestionMaker {

	public static void main(String[] args) {
		// TODO Auto-generated method stub
		
		Answers answer = new Answers();
		// Using Scanner for Getting Input from User
        Scanner in = new Scanner(System.in);
        boolean endWhy = false;
        String lastQuestion = "";
        String whyanswer;
        String whyHowAnswer;
        int whycount = 1;
        
        System.out.println("OK, lets get started with this");
        System.out.println("Instrutions: When you feel you finish to answer a question");
        System.out.println("type 1 to skip to the next question");
        System.out.println("Describe the situation then aswer the questions");
        answer.setSituation(in.nextLine());
        System.out.println("");
        System.out.println("");
        System.out.println("WHO is involved? (subject)");
        answer.setWhoAnswer(in.nextLine());
        while(!(answer.getWhoAnswer().equals("1"))){
        	lastQuestion = answer.getWhoAnswer();
        	System.out.println("");
           	System.out.println("WHO is/are " + answer.getWhoAnswer() + " ?");
        	answer.setWhoAnswer(in.nextLine());
        }
        answer.setWhoAnswer(lastQuestion);
        
        System.out.println("");
        System.out.println("");
        
        System.out.println("WHAT happened? (predicated)");
        answer.setWhatAnswer(in.nextLine());
        while(!(answer.getWhatAnswer().equals("1"))){
        	lastQuestion = answer.getWhatAnswer();
        	System.out.println("");
        	System.out.println("WHAT " + answer.getWhatAnswer() + " ?");
        	answer.setWhatAnswer(in.nextLine());
        }
        answer.setWhatAnswer(lastQuestion);
        
        System.out.println("");
        System.out.println("");
        
        System.out.println("WHERE " +answer.getWhoAnswer() + " " + answer.getWhatAnswer() + " ? (just mention place, ommit prepositions like in, at, etc)");
        answer.setWhereAnswer(in.nextLine());
        while(!(answer.getWhereAnswer().equals("1"))){
        	lastQuestion = answer.getWhereAnswer();
        	System.out.println("");
        	System.out.println("WHERE is/are " + answer.getWhereAnswer() + " ?");
        	answer.setWhereAnswer(in.nextLine());
        }
        answer.setWhereAnswer(lastQuestion);
        
        System.out.println("");
        System.out.println("");
        
        System.out.println("WHEN " +answer.getWhoAnswer() + " " + answer.getWhatAnswer() + " in " + answer.getWhereAnswer() + " ?");
        answer.setWhenAnswer(in.nextLine());
        while(!(answer.getWhenAnswer().equals("1"))){
        	lastQuestion = answer.getWhenAnswer();
        	System.out.println("");
        	System.out.println("WHEN is/are " + answer.getWhenAnswer() + " ?");
        	answer.setWhenAnswer(in.nextLine());
        }
        answer.setWhenAnswer(lastQuestion);
        
        System.out.println("");
        System.out.println("");
        
        System.out.println("WHY " +answer.getWhoAnswer() + " " + answer.getWhatAnswer() + " in " + answer.getWhereAnswer() + " when " + answer.getWhenAnswer() + " ?");
        answer.setWhyAnswer(in.nextLine());        
        while(answer.getWhyAnswer().equals("1")) {
            System.out.println("WHY " + answer.getWhyAnswer() + " ?");
            answer.setWhoAnswer(in.nextLine());
            		
            	}
       				
									
					while(endWhy == false) {
						System.out.println("");
						System.out.println("WHY"+whycount + ": why " + answer.getWhyAnswer()+ " ?");
						whyanswer = in.nextLine();
						
						if (whyanswer.equals("1")) {
							endWhy = true;
						}else {
						answer.setWhyAnswer(whyanswer);	
						whycount ++;
						}
					}
					
					System.out.println("The reason why " +answer.getWhoAnswer() + " " + answer.getWhatAnswer() + " " + answer.getWhereAnswer() + " " + answer.getWhenAnswer() + " is because: "); 
					System.out.println(answer.getWhyAnswer());
					whycount = 1;
					endWhy = false;
				
				System.out.println("");
				System.out.println("");
        	
				System.out.println("Lets see how to solve this problem:");
		        System.out.println("Write your proposal");
		        answer.setHowProposal(in.nextLine());
		        
		        System.out.println("");
				System.out.println("");
				
		        System.out.println("WHO is it about (subject)?");
		        answer.setWhoHowAnswer(in.nextLine());
		        while(!(answer.getWhoHowAnswer().equals("1"))){
		        	lastQuestion = answer.getWhoHowAnswer();
		        	System.out.println("");
		        	System.out.println("WHO is/are " + answer.getWhoHowAnswer() + " ?");
		        	answer.setWhoHowAnswer(in.nextLine());
		        }
		        answer.setWhoHowAnswer(lastQuestion);
		        
		        System.out.println("");
				System.out.println("");
				
		        System.out.println("WHAT will be done? (just describe the accion)");
		        answer.setWhatHowAnswer(in.nextLine());
		        while(!(answer.getWhatHowAnswer().equals("1"))){
		        	lastQuestion = answer.getWhatHowAnswer();
		        	System.out.println("");
		        	System.out.println("WHAT " + answer.getWhatHowAnswer() + " ?");
		        	answer.setWhatHowAnswer(in.nextLine());
		        }
		        answer.setWhatHowAnswer(lastQuestion);
		        
		        System.out.println("");
				System.out.println("");
		        
				System.out.println("HOW  " + answer.getWhatHowAnswer() + " will be done?");
		        answer.setHowHowAnswer(in.nextLine());
		        while(!(answer.getHowHowAnswer().equals("1"))){
		        	lastQuestion = answer.getHowHowAnswer();
		        	System.out.println("");
		        	System.out.println("HOW are you going to " + answer.getHowHowAnswer() + " ?");
		        	answer.setHowHowAnswer(in.nextLine());
		        }
		        answer.setHowHowAnswer(lastQuestion);
		        
		        System.out.println("");
				System.out.println("");
				
		        System.out.println("WHERE will " + answer.getWhatHowAnswer() + " " + answer.getHowHowAnswer() + " be done? (just mention place, ommit prepositions like in, at, etc)");
		        answer.setWhereHowAnswer(in.nextLine());
		        while(!(answer.getWhereHowAnswer().equals("1"))){
		        	lastQuestion = answer.getWhereHowAnswer();
		        	System.out.println("");
		        	System.out.println("WHERE is/are " + answer.getWhereHowAnswer() + " ?");
		        	answer.setWhereHowAnswer(in.nextLine());
		        }
		        answer.setWhereHowAnswer(lastQuestion);

		        System.out.println("");
				System.out.println("");
		        
		        System.out.println("WHEN will " + answer.getWhatHowAnswer() + " " + answer.getHowHowAnswer() + " in " +answer.getWhereHowAnswer()  + " be done ?");
		        answer.setWhenHowAnswer(in.nextLine());
		        while(!(answer.getWhenHowAnswer().equals("1"))){
		        	lastQuestion = answer.getWhenHowAnswer();
		        	System.out.println("");
		        	System.out.println("WHEN will be " + answer.getWhenHowAnswer() + " ?");
		        	answer.setWhenHowAnswer(in.nextLine());
		        }
		        answer.setWhenHowAnswer(lastQuestion);
		        
		        System.out.println("");
				System.out.println("");
		        
		        System.out.println("WHY the next is a good solution:");
		        System.out.println(answer.getWhatHowAnswer() + "  " + answer.getHowHowAnswer() + " in " + answer.getWhereHowAnswer() + " " + answer.getWhenHowAnswer() + " ?");
		        answer.setWhyHowAnswer(in.nextLine());
        
		        while(answer.getWhyHowAnswer().equals("1")) {
					System.out.println("You need to give reasons of why is this a good solution ");
					System.out.println("So, WHY " +answer.getWhoHowAnswer() + " " + answer.getWhatHowAnswer() + " " + answer.getWhereHowAnswer() + " " + answer.getWhenHowAnswer() + " is a good solution?");
					answer.setWhyHowAnswer(in.nextLine());
				}
					if(!(answer.getWhyHowAnswer().equals("1"))) {
												
						while(endWhy == false) {
							System.out.println("");
							System.out.println("WHY"+whycount + ": Why " + answer.getWhyHowAnswer());
							whyHowAnswer = in.nextLine();
							
							if (whyHowAnswer.equals("1")) {
								endWhy = true;
							}else {
							answer.setWhyHowAnswer(whyHowAnswer);	
							whycount ++;
							}
						}
						
					}
					
				
					System.out.println(" the reason why this is a good idea is because: ");
					System.out.println( answer.getWhyHowAnswer());
					whycount = 1;
					in.close();
        
        
        
	}

}
