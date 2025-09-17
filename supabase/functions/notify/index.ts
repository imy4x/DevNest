/// <reference types="https://deno.land/x/deno/runtime/mod.ts" />

// ملاحظة: الأخطاء التي تشير إلى "Cannot find module" لا تتعلق بالكود نفسه،
// بل ببيئة العمل. تأكد من أن محرر الأكواد لديك (مثل VS Code) مهيأ بشكل صحيح
// مع إضافة Deno لكي يتمكن من التعرف على الوحدات المستوردة من الروابط.
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.44.2'
import { create } from 'https://deno.land/x/djwt@v2.7/mod.ts'

// --- NEW V1 API HELPER FUNCTIONS ---

// Function to get an OAuth2 access token from a service account JSON
async function getAccessToken(serviceAccountJson: string): Promise<string> {
  const serviceAccount = JSON.parse(serviceAccountJson);
  const jwt = await create(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      exp: Math.floor(Date.now() / 1000) + 3600, // Expires in 1 hour
      iat: Math.floor(Date.now() / 1000),
    },
    serviceAccount.private_key
  );

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  const data = await response.json();
  if (!response.ok) {
    throw new Error(`Failed to get access token: ${data.error_description || JSON.stringify(data)}`);
  }
  return data.access_token;
}


// Rewritten function to use the V1 API
async function sendFcmNotification(tokens: string[], title: string, body: string, data = {}) {
  if (tokens.length === 0) return;

  const projectId = Deno.env.get('FCM_PROJECT_ID');
  const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');

  if (!projectId || !serviceAccountJson) {
    console.error('FCM secrets (FCM_PROJECT_ID or FCM_SERVICE_ACCOUNT_JSON) are not set.');
    return;
  }

  try {
    const accessToken = await getAccessToken(serviceAccountJson);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    
    const headers = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`,
    };

    // Send notifications one by one (suitable for small batches)
    for (const token of tokens) {
      const payload = {
        message: {
          token: token,
          notification: { title, body },
          data: { ...data, 'click_action': 'FLUTTER_NOTIFICATION_CLICK' },
        },
      };

      // We don't await inside the loop to send requests in parallel
      fetch(fcmUrl, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload),
      }).then(async (response) => {
        if (!response.ok) {
           const errorBody = await response.text();
           console.error(`FCM request for token failed with status ${response.status}:`, errorBody);
        }
      }).catch(error => {
         // تم تعديل هذا الجزء للتعامل مع الخطأ من نوع 'unknown'
         if (error instanceof Error) {
            console.error(`Error sending FCM notification for a token:`, error.message);
         } else {
            console.error(`An unknown error occurred while sending FCM notification:`, error);
         }
      });
    }
    console.log(`Attempted to send ${tokens.length} FCM notifications via V1 API.`);

  } catch (error) {
    // تم تعديل هذا الجزء للتعامل مع الخطأ من نوع 'unknown'
    if (error instanceof Error) {
        console.error('General error sending FCM notifications:', error.message);
    } else {
        console.error('An unknown general error occurred:', error);
    }
  }
}

// --- MAIN SERVER LOGIC (Mostly unchanged) ---

serve(async (req: Request) => { // تم إضافة النوع 'Request' للمتغير 'req'
  const supabaseClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
  );

  const { function_name, params } = await req.json();

  let title = '';
  let body = '';
  const tokens: string[] = [];

  const { data: { user } } = await supabaseClient.auth.getUser();
  if (!user) return new Response('Unauthorized', { status: 401 });

  // 1. Get user's own display name for notifications
  const { data: senderMember, error: senderError } = await supabaseClient
    .from('hub_members')
    .select('display_name, hub_id')
    .eq('user_id', user.id)
    .single();

  if (senderError || !senderMember) {
    console.error("Could not find sender's membership info.");
    return new Response('Sender not found in any hub', { status: 400 });
  }
  
  const senderName = senderMember.display_name ?? 'Someone';
  const hubId = senderMember.hub_id;

  // 2. Fetch all members of the hub (excluding the sender)
  const { data: members, error: membersError } = await supabaseClient
    .from('hub_members')
    .select('user_id')
    .eq('hub_id', hubId)
    .neq('user_id', user.id);
  
  if (membersError) {
    console.error('Error fetching hub members:', membersError.message);
    return new Response(membersError.message, { status: 500 });
  }

  // تم إضافة النوع للمتغير 'm'
  console.log('Fetched hub members:', members);

  const memberIds = members.map((m: { user_id: string }) => m.user_id);

  // Switch based on the called function
  switch (function_name) {
    case 'notify_new_project': {
      const { data: project } = await supabaseClient.from('projects').select('name').eq('id', params.project_id).single();
      title = 'مشروع جديد';
      body = `${senderName} أنشأ مشروعًا جديدًا: "${project?.name}"`;
      break;
    }
    case 'notify_new_bug': {
      const { data: bug } = await supabaseClient.from('bugs').select('title, project_id').eq('id', params.bug_id).single();
      const { data: project } = await supabaseClient.from('projects').select('name').eq('id', bug?.project_id).single();
      title = `جديد في مشروع "${project?.name}"`;
      body = `${senderName} أضاف: "${bug?.title}"`;
      break;
    }
    case 'notify_bug_update': {
      const { data: bug } = await supabaseClient.from('bugs').select('title, project_id, status').eq('id', params.bug_id).single();
      const { data: project } = await supabaseClient.from('projects').select('name').eq('id', bug?.project_id).single();
      title = `تحديث في مشروع "${project?.name}"`;
      body = `${senderName} قام بتحديث حالة "${bug?.title}" إلى "${bug?.status}"`;
      break;
    }
     case 'notify_new_chat_message': {
      const { data: project } = await supabaseClient.from('projects').select('name').eq('id', params.project_id).single();
      title = `رسالة جديدة في "${project?.name}"`;
      body = `${senderName}: ${params.message.substring(0, 50)}...`;
      break;
    }
    case 'notify_project_update': {
       const { data: project } = await supabaseClient.from('projects').select('name').eq('id', params.project_id).single();
       title = 'تحديث تفاصيل المشروع';
       body = `${senderName} قام بتحديث تفاصيل مشروع "${project?.name}"`;
       break;
    }
    case 'notify_test_broadcast': {
  title = 'إشعار اختبار';
  body = `هذا إشعار تجريبي لجميع أعضاء الـ Hub "${hubId}"`;
  break;
}

    case 'notify_permissions_update': {
      const { data: targetMember } = await supabaseClient.from('hub_members').select('display_name, user_id').eq('id', params.member_id).single();
      title = 'تحديث الصلاحيات';
      body = `قام القائد بتحديث صلاحياتك في الفريق.`;
      memberIds.length = 0; // Clear the array
      if(targetMember?.user_id) memberIds.push(targetMember.user_id); // Only target this user
      break;
    }
    case 'notify_member_removed': {
       const { data: targetMember } = await supabaseClient.from('hub_members').select('display_name, user_id').eq('id', params.member_id).single();
       title = 'إزالة من الفريق';
       body = `لقد تمت إزالتك من الفريق بواسطة القائد.`;
       memberIds.length = 0;
       if(targetMember?.user_id) memberIds.push(targetMember.user_id);
       break;
    }
    case 'notify_broadcast':
case 'notify_test_broadcast': {
  title = params.title ?? 'إشعار لجميع الأعضاء';
  body = params.body ?? `هذا إشعار لجميع أعضاء الـ Hub "${hubId}"`;

  // اجعل memberIds يحتوي على كل أعضاء الـ Hub
  memberIds.length = 0; // فرغ أي بيانات سابقة
  if (members) {
    memberIds.push(...members.map((m: { user_id: string }) => m.user_id));
  }
  break;
}

    default:
      return new Response('Invalid function name', { status: 400 });
  }

  // 3. Fetch device tokens for the target members
  if (memberIds.length > 0) {
      const { data: devices, error: devicesError } = await supabaseClient
        .from('user_devices')
        .select('device_token')
        .in('user_id', memberIds);

      if (devicesError) {
        console.error('Error fetching device tokens:', devicesError.message);
        return new Response(devicesError.message, { status: 500 });
      }
      
      // تم إضافة النوع للمتغير 'd'
      if(devices) tokens.push(...devices.map((d: { device_token: string }) => d.device_token));
  }
 
  // 4. Send the notification
  console.log('Tokens to send notification:', tokens);

  await sendFcmNotification(tokens, title, body);

  return new Response(JSON.stringify({ success: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
});
// تم حذف القوس المعقوف الزائد من نهاية الملف
